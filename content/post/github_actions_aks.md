+++
Categories = ["GitHub"]
Tags = ["GitHub", "Azure", "Kubernetes"]
date = "2018-12-22T20:00:00+09:00"
title = "GitHub ActionsでAzure CLIとkubectlを動かす"

+++

## GitHub Actionsのプレビュー招待がきた

ので試します。プレビュー中なので細かいことは抜きに、ざっくりどんなことができるか。

[GitHub Actions](https://developer.github.com/actions/)

数時間、触った印象。

* GitHubへのPushなどイベントをトリガーにWorkflowを流せる
* シンプルなWorkflow記法 (TerraformのHCLに似ている)
* Workflowから呼び出すActionはDockerコンテナー
* Dockerコンテナーをビルドしておかなくてもいい (Dockerfileをリポジトリに置けば実行時にビルドされる)

Dockerに慣れていて、ちょっとしたタスクの自動化を、GitHubで完結したい人に良さそうです。

## Azure CLI/Kubernetes(AKS) kubectlサンプル

こんなことを試してみました。

* KubernetesのマニフェストをGitHubリポジトリへPush
* PushイベントをトリガーにWorkflowを起動
* Azure CLIを使ってAKSクラスターのCredentialを取得
* イベント発生元がmasterブランチであれば継続
* kubectl applyでマニフェストを適用

kubectlを制限したい、証明書を配るのめんどくさい、なのでGitHubにPushされたらActionsでデプロイ、ってシナリオです。がっつり使うにはまだ検証足らずですが、ひとまずできることは確認しました。

コードは [ここ](https://github.com/ToruMakabe/actions-playground) に。

ディレクトリ構造は、こうです。

```
.
├── .git
│   └── (省略)
├── .github
│   └── main.workflow
├── LICENSE
├── README.md
├── azure-cli
│   ├── Dockerfile
│   └── entrypoint.sh
└── sampleapp.yaml
```

* .github の下にWorkflowを書きます
* azure-cli の下に自作Actionを置きました
* sampleapp.yaml がkubernetesのマニフェストです

### Workflow

まず、 .github/main.workflow を見てみましょう

```
workflow "Deploy app to AKS" {
  on = "push"
  resolves = ["Deploy to AKS"]
}

action "Load AKS credential" {
  uses = "./azure-cli/"
  secrets = ["AZURE_SERVICE_APP_ID", "AZURE_SERVICE_PASSWORD", "AZURE_SERVICE_TENANT"]
  args = "aks get-credentials -g $AKS_RG_NAME -n $AKS_CLUSTER_NAME -a"
  env = {
    AZ_OUTPUT_FORMAT = "table"
    AKS_RG_NAME = "your-aks-rg"
    AKS_CLUSTER_NAME = "youraks"
  }
}

action "Deploy branch filter" {
  uses = "actions/bin/filter@master"
  args = "branch master"
}

action "Deploy to AKS" {
  needs = ["Load AKS credential", "Deploy branch filter"]
  uses = "docker://gcr.io/cloud-builders/kubectl"
  runs = "sh -l -c"
  args = ["cat $GITHUB_WORKSPACE/sampleapp.yaml |  sed -e 's/YOUR_VALUE/'\"$YOUR_VALUE\"'/' -e 's/YOUR_DNS_LABEL_NAME/'$YOUR_DNS_LABEL_NAME'/' | kubectl apply -f - "]
  env = {
    YOUR_VALUE = "Ale"
    YOUR_DNS_LABEL_NAME = "yournamedispvar"
  }
}
```

シンプルですね。全体を定義するworkflowブロックと、それぞれのActionを書くactionブロックがあります。記法やオプションは[ドキュメント](https://developer.github.com/actions/creating-workflows/)を読めばだいたい分かります。依存関係はneedsで書ける。

それぞれのactionブロックでDockerコンテナーを呼び出します。usesで指定したディレクトリにDockerファイルをおいておけばビルドされ、そのactionで使えます。"Load AKS credential"ブロックがその例です。"./azure-cli/"にDockerfileとエントリーポイントとなるbashスクリプトを置きます。

"Deploy branch filter"ブロックは[GitHub Actionsが提供している](https://github.com/actions)コンテナーの、"Deploy to AKS"は外部Dockerレジストリーを利用した例です。詳しくは後ほど。

リポジトリでPushイベントが発生すると、Workflowが実行されます。リポジトリの"Actions"タブで実行結果を確認できます。

![Workflow](https://raw.githubusercontent.com/ToruMakabe/Images/master/ghaction_sc.png)

できた。Azure CLIとkubectlが使えるなら、他にも応用できそう。

以下、actionブロックを補足します。

### Load AKS credential

Azure CLIを使ってAKSクラスターのCredentialを取得し、kubectlのコンテキスト設定します。envでクラスターのリソースグループ名とクラスター名を渡しています。

GitHub ActionsがAzure CLI Actionを[提供している](https://github.com/actions/azure)のですが、Azure CLIのバージョンを最新にしたかったのと、動的にコンテナーを作ってみたかったので ./azure-cli にDockerfileを[書きました](https://github.com/ToruMakabe/actions-playground/tree/master/azure-cli)。

試す時は、みなさんの環境向けにenvを書き換えてください。なお、AKSクラスターからCredentialを取得する権限が必要です。権限を持ったサービスプリンシパルのアプリケーションID/パスワード、テナントIDをGitHubリポジトリのSecretに設定してください。actionブロックのsecretsで指定している通りです。

### Deploy branch filter

bin/filterはGitHub Actionsが[提供している](https://github.com/actions/bin)ユーティリティです。この例では、イベントがmasterブランチで発生した場合のみWorkflowを継続します。

### Deploy to AKS

gcr.ioからkubectlコンテナーを取得し、実行しています。マニフェストの一部を動的に変えたいことは多いので、sedでマニフェストの一部を置換する例にしました。

このactionが実行されると、envの"YOUR_VALUE"にセットした文字列を表示する[Golang Webアプリ](https://github.com/ToruMakabe/container-simpledemo/blob/master/displayEnvVar/main.go)のDeploymentと公開用のServiceができます。"YOUR_DNS_LABEL_NAME"にはDNSラベル名を指定でき、FQDNはAKSクラスターの配置リージョンに応じて決定されます。東日本リージョンの場合、YOUR_DNS_LABEL_NAME.japaneast.cloudapp.azure.com となります。

アプリのパスは /dispvar です。curlしてみると。

```
$ curl http://yournamedispvar.japaneast.cloudapp.azure.com/dispvar
Hello. You set "Ale"
```

## まとめ

Dockerに慣れていれば便利に使えるかな、という印象です。Terraformのfmt/validate/plan用Actionなども[公開されています](https://www.terraform.io/docs/github-actions/index.html)。がっつりパイプラインを作らないとしても、コードのフォーマットや構文チェックに良さそうです。