+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform"]
date = "2018-01-08T16:30:00+09:00"
title = "TerraformでAzure サンプル 2018/1版"

+++

## サンプルのアップデート
年末にリポジトリの大掃除をしていて、2年前に書いたTerraform & Azureの[記事](http://torumakabe.github.io/post/azure_tf_fundamental_rules/)に目が止まりました。原則はいいとして、[サンプル](https://github.com/ToruMakabe/Terraform_Azure_Sample)は2年物で腐りかけです。ということでアップデートします。

## インパクトの大きな変更点
Terraformの、ここ2年の重要なアップデートは以下でしょうか。Azure視点で。

1. BackendにAzure Blobを使えるようになった
2. Workspaceで同一コード・複数環境管理ができるようになった
3. 対応リソースが増えた
4. [Terraform Module Registry](https://registry.terraform.io/)が公開された

## 更新版サンプルの方針
重要アップデートをふまえ、以下の方針で新サンプルを作りました。

### チーム、複数端末での運用
BackendにAzure Blobがサポートされたので、チーム、複数端末でstateの共有がしやすくなりました。ひとつのプロジェクトや環境を、チームメンバーがどこからでも、だけでなく、複数プロジェクトでのstate共有もできます。

### Workspaceの導入
従来は /dev /stage /prodなど、環境別にコードを分けて管理していました。ゆえに環境間のコード同期が課題でしたが、TerraformのWorkspace機能で解決しやすくなりました。リソース定義で ${terraform.workspace} 変数を参照するように書けば、ひとつのコードで複数環境を扱えます。

要件によっては、従来通り環境別にコードを分けた方がいいこともあるでしょう。環境間の差分が大きい、開発とデプロイのタイミングやライフサイクルが異なるなど、Workspaceが使いづらいケースもあるでしょう。その場合は無理せず従来のやり方で。今回のサンプルは「Workspaceを使ったら何ができるか？」を考えるネタにしてください。

### Module、Terraform Module Registryの活用
TerraformのModuleはとても強力な機能なのですが、あーでもないこーでもないと、こだわり過ぎるとキリがありません。「うまいやり方」を見てから使いたいのが人情です。そこでTerraform Module Registryを活かします。お墨付きのVerifiedモジュールが公開されていますので、そのまま使うもよし、ライセンスを確認の上フォークするのもよし、です。

### リソースグループは環境ごとに準備し、管理をTerraformから分離
AzureのリソースをプロビジョニングするTerraformコードの多くは、Azureのリソースグループを管理下に入れている印象です。すなわちdestroyするとリソースグループごとバッサリ消える。わかりやすいけど破壊的。

TerraformはApp ServiceやACIなどPaaS、アプリ寄りのリソースも作成できるようになってきたので、アプリ開発者にTerraformを開放したいケースが増えてきています。dev環境をアプリ開発者とインフラ技術者がコラボして育て、そのコードをstageやprodにデプロイする、など。

ところで。TerraformのWorkspaceは、こんな感じで簡単に切り替えられます。

```
terraform workspace select prod
```

みなまで言わなくても分かりますね。悲劇はプラットフォーム側で回避しましょう。今回のサンプルではリソースグループをTerraform管理下に置かず、別途作成します。Terraformからはdata resourcesとしてRead Onlyで参照する実装です。環境別のリソースグループを作成し、dev環境のみアプリ開発者へ権限を付与します。

## サンプル解説
サンプルは[GitHub](https://github.com/ToruMakabe/Terraform_Azure_Sample_201801)に置きました。合わせてご確認ください。

このコードをapplyすると、以下のリソースが出来上がります。

* NGINX on Ubuntu Webサーバー VMスケールセット
* VMスケールセット向けロードバランサー
* 踏み台サーバー
* 上記を配置するネットワーク (仮想ネットワーク、サブネット、NSG)

### リポジトリ構造
サンプルのリポジトリ構造です。

```
├── modules
│   ├── computegroup
│   │   ├── main.tf
│   │   ├── os
│   │   │   ├── outputs.tf
│   │   │   └── variables.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── loadbalancer
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── network
│       ├── main.tf
│       ├── outputs.tf
│       └── variables.tf
└── projects
    ├── project_a
    │   ├── backend.tf
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── variables.tf
    └── shared
        ├── backend.tf
        ├── main.tf
        ├── outputs.tf
        └── variables.tf
```

/modulesには[Terraform Module Registry](https://registry.terraform.io/browse?provider=azurerm)でVerifiedされているモジュールをフォークしたコードを入れました。フォークした理由は、リソースグループをdata resource化して参照のみにしたかったためです。

そして、/projectsに2つのプロジェクトを作りました。プロジェクトでリソースとTerraformの実行単位、stateを分割します。sharedで土台となる仮想ネットワークと踏み台サーバー関連リソース、project_aでVMスケールセットとロードバランサーを管理します。

このボリュームだとプロジェクトを分割する必然性は低いのですが、以下のケースにも対応できるように分けました。

* アプリ開発者がproject_a下でアプリ関連リソースに集中したい
* 性能観点で分割したい (Terraformはリソース量につれて重くなりがち)
* 有事を考慮し影響範囲を分割したい

プロジェクト間では、stateをremote_stateを使って共有します。サンプルではsharedで作成した仮想ネットワークのサブネットIDを[output](https://github.com/ToruMakabe/Terraform_Azure_Sample_201801/blob/master/projects/shared/outputs.tf#L1)し、project_aで参照できるよう[定義](https://github.com/ToruMakabe/Terraform_Azure_Sample_201801/blob/master/projects/project_a/backend.tf.sample#L10)しています。

## 使い方

### 前提

* Linux、WSL、macOSなどbash環境の実行例です
* SSHの公開鍵をTerraform実行環境の ~/.ssh/id_rsa.pub として準備してください

### 管理者向けのサービスプリンシパルを用意する
インフラのプロビジョニングの主体者、管理者向けのサービスプリンシパルを用意します。リソースグループを作成できる権限が必要です。

もしなければ作成します。組み込みロールでは、サブスクリプションに対するContributorが妥当でしょう。[Terraformのドキュメント](https://www.terraform.io/docs/providers/azurerm/authenticating_via_service_principal.html)も参考に。

```
az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/SUBSCRIPTION_ID"
```

出力されるappId、password、tenantを控えます。既存のサービスプリンシパルを使うのであれば、同情報を確認してください。

なお参考までに。Azure Cloud ShellなどAzure CLIが導入されている環境では、特に認証情報の指定なしでterraform planやapply時にAzureのリソースにアクセスできます。TerraformがCLIの認証トークンを[使う](https://github.com/terraform-providers/terraform-provider-azurerm/blob/master/azurerm/helpers/authentication/config.go)からです。

そしてBackendをAzure Blobとする場合、Blobにアクセスするためのキーが別途必要です。ですが、残念ながらBackendロジックでキーを得る際に、このトークンが[使われません](https://github.com/hashicorp/terraform/blob/master/backend/remote-state/azure/backend.go)。キーを明示することもできますが、Blobのアクセスキーは漏洩時のリカバリーが大変です。できれば直に扱いたくありません。

サービスプリンシパル認証であれば、Azureリソースへのプロビジョニング、Backendアクセスどちらも[対応できます](https://www.terraform.io/docs/backends/types/azurerm.html)。これがこのサンプルでサービスプリンシパル認証を選んだ理由です。

### 管理者の環境変数を設定する
Terraformが認証関連で必要な情報を環境変数で設定します。先ほど控えた情報を使います。

```
export ARM_SUBSCRIPTION_ID="<your subscription id>"
export ARM_CLIENT_ID="<your servicce principal appid>"
export ARM_CLIENT_SECRET="<your service principal password>"
export ARM_TENANT_ID="<your service principal tenant>"
```

### Workspaceを作る
開発(dev)/ステージング(stage)/本番(prod)、3つのWorkspaceを作る例です。

```
terraform workspace new dev
terraform workspace new stage
terraform workspace new prod
```

### リソースグループを作る
まずWorkspace別にリソースグループを作ります。

```
az group create -n tf-sample-dev-rg -l japaneast
az group create -n tf-sample-stage-rg -l japaneast
az group create -n tf-sample-prod-rg -l japaneast
```

リソースグループ名にはルールがあります。Workspace別にリソースグループを分離するため、Terraformのコードで ${terraform.workspace} 変数を使っているためです。この変数は実行時に評価されます。

```
data "azurerm_resource_group" "resource_group" {
  name = "${var.resource_group_name}-${terraform.workspace}-rg"
}
```

${var.resource_group_name} は接頭辞です。サンプルではvariables.tfで"tf-sample"と指定しています。

次にBackend、state共有向けリソースグループを作ります。

```
az group create -n tf-sample-state-rg -l japaneast
```

このリソースグループは、各projectのbackend.tfで指定しています。

```
terraform {
  backend "azurerm" {
    resource_group_name  = "tf-sample-state-rg"
    storage_account_name = "<your storage account name>"
    container_name       = "tfstate-project-a"
    key                  = "terraform.tfstate"
  }
}
```

最後にアプリ開発者がリソースグループtf-sample-dev-rg、tf-sample-state-rgへアクセスできるよう、アプリ開発者向けサービスプリンシパルを作成します。

```
az ad sp create-for-rbac --role="Contributor" --scopes "/subscriptions/<your subscription id>/resourceGroups/tf-sample-dev-rg" "/subscriptions/<your subscription id>/resourceGroups/tf-sample-state-rg"
```

出力されるappId、password、tenantは、アプリ開発者向けに控えておきます。

### Backendを準備する
project別にストレージアカウントとコンテナーを作ります。tf-sample-state-rgに

* ストレージアカウント (名前は任意)
* コンテナー *2 (tfstate-project-a, tfstate-shared)

を作ってください。GUIでもCLIでも、お好きなやり方で。

その後、project_a/backend.tf.sample、shared/backend.tf.sampleをそれぞれbackend.tfにリネームし、先ほど作ったストレージアカウント名を指定します。以下はproject_a/backend.tf.sampleの例。

```
terraform {
  backend "azurerm" {
    resource_group_name  = "tf-sample-state-rg"
    storage_account_name = "<your storage account name>"
    container_name       = "tfstate-project-a"
    key                  = "terraform.tfstate"
  }
}

data "terraform_remote_state" "shared" {
  backend = "azurerm"

  config {
    resource_group_name  = "tf-sample-state-rg"
    storage_account_name = "<your storage account name>"
    container_name       = "tfstate-shared"
    key                  = "terraform.tfstateenv:${terraform.workspace}"
  }
}
```

これで準備完了です。

### 実行
Workspaceをdevに切り替えます。

```
terraform workspace select dev
```

まずは土台となるリソースを作成するsharedから。

```
cd shared
terraform init
terraform plan
terraform apply
```

土台となるリソースが作成されたら、次はprocject_aを。

```
cd ../project_a
terraform init
terraform plan
terraform apply
```

ここでは割愛しますが、dev向けサービスプリンシパルで認証しても、dev Workspaceではplan、apply可能です。

dev Workspaceでコードが育ったら、stage/prod Workspaceに切り替えて実行します。

```
terraform workspace select stage
[以下devと同様の操作]
```

当然、dev向けサービスプリンシパルで認証している場合は、stage/prodでのplan、apply、もちろんdestroyも失敗します。stage/prod リソースグループにアクセスする権限がないからです。

## 参考情報

* [Terraform on Azure のドキュメント](https://docs.microsoft.com/ja-jp/azure/terraform/)
* [サンプル集 on GitHub](https://github.com/terraform-providers/terraform-provider-azurerm/tree/master/examples)