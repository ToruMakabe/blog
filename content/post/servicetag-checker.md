+++
Categories = ["Azure"]
Tags = ["Azure","Github","Go"]
date = "2021-02-25T13:30:00+09:00"
title = "Goで書いたAzureのハウスキーピングアプリをContainer InstancesとGitHub Actionsで定期実行する"

+++

## 何の話か

以下のようなご相談をいただき、とても共感したのでサンプルを作りました。

* 運用系で定期実行したい作業、いわゆるハウスキーピング/レポーティング処理がある
* いずれその機能はサービスとして提供されそう/リクエストしているが、それまでの間をつなぐ仕組みを作りたい
* KubernetesやTerraformなど、利用しているOSSの習熟も兼ねて、Goで書きたい
* Azureのリソースを操作するので、権限割り当てやシークレット管理は気を付けたい、アプリのコードに書くなんてもってのほか
* ハウスキーピングアプリだけでなく環境全体をコード化し、ライフサイクル管理したい
  * いずれこの仕組みが不要になったらサクッと消す

## 作ったもの

例として、ネットワークサービスタグの変更を日次でチェックし、差分をレポートするアプリを作りました。[Service Tag Discovery API](https://docs.microsoft.com/ja-jp/rest/api/virtualnetwork/servicetags/list)を使います。Azure系サービスが利用しているIPアドレスのレンジの一覧を取得できるアレです。取得したタグデータをblobに保存しておき、次回以降は取得したタグとの差分があればレポートを作成します。最近ではIPレンジを抜き出さなくともタグの指定すれば済むサービスが増えてきたのですが、根強いニーズがあるのでサンプルにいいかな、と思いました。このサンプルはレポート止まりですが、慣れたらリソースの追加変更に取り組んでもいいでしょう。

{{< figure src="https://raw.githubusercontent.com/ToruMakabe/Images/master/servicetags-checker-1.jpg?raw=true" width="500">}}

* GitHub Actionsのスケジュール機能で日次実行
* アプリ実行環境はAzure Container Instances
* アプリのAzureリソース認証認可はManaged Identityを利用
* APIから取得したタグデータ、作成した差分レポートはblobへ保管
* 実行ログをAzure Monitor Log Analyticsに転送し、変更レポート作成イベントログを検出したらメールで通知

環境はTerraformでライフサイクル管理します。

{{< figure src="https://raw.githubusercontent.com/ToruMakabe/Images/master/servicetags-checker-2.jpg?raw=true" width="600">}}

* 必要なリソース作成や権限割り当ては全てTerraformで行う
* GitHubリポジトリへのシークレット登録もTerraformで実行

環境だけでなくアプリも同じリポジトリに入れてライフサイクル管理します。

{{< figure src="https://raw.githubusercontent.com/ToruMakabe/Images/master/servicetags-checker-3.jpg?raw=true" width="400">}}

* ブランチへのプッシュをトリガーにアプリのCI(単体テスト)が走る
* バージョン規約(セマンティックバージョニング)を満たすタグのプッシュをトリガーに、コンテナのビルドとAzure Container Registryへのプッシュを実行

コードはGitHubに[公開](https://github.com/ToruMakabe/az-servicetags-checker-go)しています。

## 考えたことメモ

作りながら考えたことが参考になるかもしれないので、残しておきます。

* ハウスキーピングアプリの実行環境として、Azure FunctionsやLogic Appsもありです。それらを手の内に入れており、言語にこだわりがなければ、そのほうが楽かも
* FunctionsであればGoを[カスタムハンドラー](https://docs.microsoft.com/ja-jp/azure/azure-functions/functions-custom-handlers)で動かす手もあります。ただ、ユースケースが定期実行、つまりタイマトリガだと、入出力バインディングなどFunctionsのおいしいところを活かせないので、あえてカスタムハンドラを使って書くこともないかな、という気持ちに
* Rustで書いちゃおっかな、とも思ったのですが、Azure SDK for Rustが現状 ["very active development"](https://github.com/Azure/azure-sdk-for-rust)なので、この用途では深呼吸
* GoはAzure SDKのファーストクラス言語ではありませんが、KubernetesやTerraformのAzure対応で活発に利用されており、実用的です。ただ、Azureリソースの管理系操作、つまり[コントロールプレーン](https://github.com/Azure/azure-sdk-for-go)と、blobの操作など[データプレーン](https://github.com/Azure/azure-sdk-for-go#other-azure-go-packages)向けSDKが分離されているので注意が必要です
  * どちらかだけならいいのですが、このサンプルのようにどちらも使うケースで課題になる
  * このサンプルでは[Giovanni](https://github.com/tombuildsstuff/giovanni)や[Terraform AzureRM Provider](https://github.com/terraform-providers/terraform-provider-azurerm/blob/e1fc6984b5b5c75658f80552e40459b44eb3bd4a/azurerm/internal/clients/builder.go)を参考に、クライアントビルダーをまとめた
* リトライは大事です。コケても再実行できるようにしましょう
  * 例えば、このサンプルではAzure Container InstancesのManaged Identityサポートが作成時点で[プレビュー](https://docs.microsoft.com/ja-jp/azure/container-instances/container-instances-managed-identity)ということもあり、[Managed Identityエンドポイントの準備が整う前にコンテナが起動する](https://feedback.azure.com/forums/602224-azure-container-instances/suggestions/40834543-wait-for-the-managed-identity-endpoint-to-be-avail)ケースが報告されています
  * このサンプルのように常時起動が不要なケースでは、Azure Container Instancesを[--restart-policy OnFailure](https://docs.microsoft.com/ja-jp/azure/container-instances/container-instances-restart-policy)オプションで起動すれば、異常終了時に再実行されます。また、正常終了時にはコンテナが停止し課金も止まります
* Actionsでの認証認可やAzure Container Instancesの実行パラメータ用途で、GitHubに登録するシークレットが多めです。Terraform実行時に.tfvarsや環境変数で渡す想定ですが、やはり扱うシークレットは少なく、シンプルに、できれば自分で登録しないほうがいいです。各サービスや機能でシークレットの扱いはニーズに合わせてこまめに改善される傾向にあるので、定期的に見直しましょう
  * 例えば[これ](https://github.com/Azure/login/issues/39)
  * GitHubの[Organization secrets](https://github.blog/changelog/2020-05-14-organization-secrets/)などもご活用を
* もしハウスキーピング操作がAzure CLIで完結するなら、GitHub Actionsだけでやったほうが楽です。例えば[こんな感じ](https://docs.microsoft.com/ja-jp/azure/aks/node-upgrade-github-actions)で
