+++
Categories = ["GitHub"]
Tags = ["GitHub", "Azure"]
date = "2019-12-22T23:30:00+09:00"
title = "GitHub Actionsでオンデマンドに環境を再現する"

+++

## 何の話か

GitHubでインフラや環境を作るコードを管理している人は多いと多います。そして最近はGitHub Actionsを使ったワークフローに取り組むケースも増えてきました。

* プルリクエストイベントをトリガーにコードの検証やテストを行い、マージの判断に使う
* マージされたら、ステージングや本番環境へデプロイする

こんなワークフローが一般的と思います。ですが一時的に「コードは変えてないけど、一時的に環境を再現したい」なんてこともあります。不具合対応とか。環境を作るコードはあるので、どこかにコードを持っていって実行すればいいのですが、せっかくGitHub Actionsで仕組みを作った手前、チョイっといじってできるなら、そうしたい。

## アイデア

GitHub Actionsを使ってコードから環境をデプロイする環境はすでにある、という前提なので、論点は「どのトリガーを使うか」です。

> [ワークフローをトリガーするイベント](https://help.github.com/ja/actions/automating-your-workflow-with-github-actions/events-that-trigger-workflows)

トリガーにできるイベントは多くありますが「コードは変えない」という条件だと、悩みます。プルリクやプッシュでの発火がわかりやすいからといって、そのためのフラグファイル的なものを作りたくもありません。

GitHubでコミュニケーションしているのであれば、環境を再現したいような事案発生時にはIssueを作るでしょう。であれば、特定のキーワードを含むIssueを作った/消したタイミングで発火させましょうか。でもこのやり口では、チェックなしで環境が作られてしまいます。それがプライベートリポジトリであっても、気前良すぎ良太郎な感は否めません。

そこで、Issueイベントのタイプ labeled/unlabeled を使ってみましょう。ラベルを付与できるのはTriage以上の権限を持った人です。権限を持った人がIssueに「環境を再現」するラベルを付け/外しした時に発火するようなワークフローを作ります。

## ワークフロー例

以下、Azureで環境を作る例です。ラベルがIssueに付く、外れるのを契機にワークフローが流れ、条件を満たした場合に環境のデプロイか削除を行います。インフラのコード化はAzure Resource Managerテンプレートでされており、ファイルはリポジトリの deployment/azuredeploy.json に置かれている、というサンプルです。

```yaml
name: gh-actions-trigger-labeled

on:
  issues:
    types:
      - labeled
      - unlabeled
env:
  AZURE_GROUP_NAME: rg-repro-gh-actions-trigger-label
  YOUR_PARAM: hoge

jobs:
  deploy-or-delete:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@master

      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - if: github.event.label.name == 'repro' && github.event.action == 'labeled'
        run: |
          az group create -n ${{ env.AZURE_GROUP_NAME }} -l japaneast
          az group deployment create -n repro -g ${{ env.AZURE_GROUP_NAME }} --template-file deployment/azuredeploy.json --parameters name=${{ env.YOUR_PARAM }}

      - if: github.event.label.name == 'repro' && github.event.action == 'unlabeled'
        run: |
          az group delete -n ${{ env.AZURE_GROUP_NAME }} -y

      - run: |
          az logout
```

ポイントは以下の通りです。

* ラベル「repro」を作っておく(環境を再現してるという意図が分かればなんでも)
* if文でステップ実行の条件を書く
  * ラベルがIssueに付与され、それがreproだった場合にAzure CLIでリソースグループ作成、テンプレートデプロイが実行される
  * ラベルが外され、それがreproだった場合にAzure CLIでリソースグループごと削除する
* 環境の違いはパラメーターで注入する
  * この例ではenvで定義したパラメーターをテンプレートデプロイのパラメーターとして渡している
* Issueトリガーで対象となるブランチはデフォルトブランチ
* この例は再現環境をリポジトリで1つとしたケース
  * 他のIssueでラベルを付けられてもいいように、繰り返し実行可能な作りにする
  * Azure Resource Manager テンプレートデプロイはが既存リソースがあった時、投入内容が同じであれば[実行されない](https://docs.microsoft.com/ja-jp/azure/azure-resource-manager/deployment-modes)が、動的にパラメーターを作っている場合は気を付けましょう
  * Issueごとに環境をつくりたい場合は、github.event.issue.idなどを活用してリソースを作る
* イベントのペイロードは[公式サイト](https://developer.github.com/v3/activity/events/types/)を参考に

Terraformでも同じようにやりたいところですが、残念ながら terraform-github-actions がdestroyに未対応です。[プルリク](https://github.com/hashicorp/terraform-github-actions/pull/77)は出ているので期待しましょう。なお、GitHub Actionsは発火までにして、以降のデプロイは[Azure Pipelinesに任せてしまう](https://github.com/Azure/pipelines)、という手もあります。

ラベルを駆使するリポジトリでは、その度にワークフローが走ってしまうのが気になる方法ではありますが、ご参考になれば。
