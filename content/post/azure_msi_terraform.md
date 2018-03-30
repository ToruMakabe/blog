+++
Categories = ["Azure"]
Tags = ["Azure", "MSI", "Terraform"]
date = "2018-03-30T16:30:00+09:00"
title = "Azure MarketplaceからMSI対応でセキュアなTerraform環境を整える"

+++

## TerraformのプロビジョニングがMarketplaceから可能に
Terraform使ってますか。Azureのリソースプロビジョニングの基本はAzure Resource Manager Template Deployである、がわたしの持論ですが、Terraformを使う/併用する方がいいな、というケースは結構あります。使い分けは[この資料](https://www.slideshare.net/ToruMakabe/azure-infrastructure-as-code)も参考に。

さて、先日Azure Marketplaceから[Terraform入りの仮想マシン](https://azuremarketplace.microsoft.com/en-us/marketplace/apps/azure-oss.terraform)をプロビジョニングできるようになりました。Ubuntuに以下のアプリが導入、構成されます。

* Terraform (latest)
* Azure CLI 2.0
* Managed Service Identity (MSI) VM Extension
* Unzip
* JQ
* apt-transport-https

いろいろセットアップしてくれるのでしみじみ便利なのですが、ポイントはManaged Service Identity (MSI)です。

## シークレットをコードにベタ書きする問題
MSIの何がうれしいいのでしょう。分かりやすい例を挙げると「GitHubにシークレットを書いたコードをpushする、お漏らし事案」を避ける仕組みです。もちそんそれだけではありませんが。

[Azure リソースの管理対象サービス ID (MSI)](https://docs.microsoft.com/ja-jp/azure/active-directory/managed-service-identity/overview)

詳細の説明は公式ドキュメントに譲りますが、ざっくり説明すると

**アプリに認証・認可用のシークレットを書かなくても、アプリの動く仮想マシン上にあるローカルエンドポイントにアクセスすると、Azureのサービスを使うためのトークンが得られるよ**

です。

GitHub上に疑わしいシークレットがないかスキャンする[取り組み](https://azure.microsoft.com/ja-jp/blog/managing-azure-secrets-on-github-repositories/)もはじまっているのですが、できればお世話になりなくない。MSIを活用しましょう。

## TerraformはMSIに対応している
TerraformでAzureのリソースをプロビジョニングするには、もちろん認証・認可が必要です。従来はサービスプリンシパルを作成し、そのIDやシークレットをTerraformの実行環境に配布していました。でも、できれば配布したくないですよね。実行環境を特定の仮想マシンに限定し、MSIを使えば、解決できます。

ところでMSIを使うには、ローカルエンドポイントにトークンを取りに行くよう、アプリを作らなければいけません。

[Authenticating to Azure Resource Manager using Managed Service Identity](https://www.terraform.io/docs/providers/azurerm/authenticating_via_msi.html)

Terraformは対応済みです。環境変数 ARM_USE_MSI をtrueにしてTerraformを実行すればOK。

## 試してみよう
実は、すでに使い方を解説した公式ドキュメントがあります。

[Azure Marketplace イメージを使用して管理対象サービス ID を使用する Terraform Linux 仮想マシンを作成する](https://docs.microsoft.com/ja-jp/azure/terraform/terraform-vm-msi)

手順は十分なのですが、理解を深めるための補足情報が、もうちょっと欲しいところです。なので補ってみましょう。

### MarketplaceからTerraform入り仮想マシンを作る
まず、Marketplaceからのデプロイでどんな仮想マシンが作られたのか、気になります。デプロイに利用されたテンプレートをのぞいてみましょう。注目は以下3つのリソースです。抜き出します。

* MSI VM拡張の導入
* VMに対してリソースグループスコープでContributorロールを割り当て
* スクリプト実行 VM拡張でTerraform関連のプロビジョニング

```
[snip]
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "[concat(parameters('vmName'),'/MSILinuxExtension')]",
            "apiVersion": "2017-12-01",
            "location": "[parameters('location')]",
            "properties": {
                "publisher": "Microsoft.ManagedIdentity",
                "type": "ManagedIdentityExtensionForLinux",
                "typeHandlerVersion": "1.0",
                "autoUpgradeMinorVersion": true,
                "settings": {
                    "port": 50342
                },
                "protectedSettings": {}
            },
            "dependsOn": [
                "[concat('Microsoft.Compute/virtualMachines/', parameters('vmName'))]"
            ]
        },
        {
            "type": "Microsoft.Authorization/roleAssignments",
            "name": "[variables('resourceGuid')]",
            "apiVersion": "2017-09-01",
            "properties": {
                "roleDefinitionId": "[variables('contributor')]",
                "principalId": "[reference(concat(resourceId('Microsoft.Compute/virtualMachines/', parameters('vmName')),'/providers/Microsoft.ManagedIdentity/Identities/default'),'2015-08-31-PREVIEW').principalId]",
                "scope": "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', resourceGroup().name)]"
            },
            "dependsOn": [
                "[resourceId('Microsoft.Compute/virtualMachines/extensions/', parameters('vmName'),'MSILinuxExtension')]"
            ]
        },
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "[concat(parameters('vmName'),'/customscriptextension')]",
            "apiVersion": "2017-03-30",
            "location": "[parameters('location')]",
            "properties": {
                "publisher": "Microsoft.Azure.Extensions",
                "type": "CustomScript",
                "typeHandlerVersion": "2.0",
                "autoUpgradeMinorVersion": true,
                "settings": {
                    "fileUris": [
                        "[concat(parameters('artifactsLocation'), '/scripts/infra.sh', parameters('artifactsLocationSasToken'))]",
                        "[concat(parameters('artifactsLocation'), '/scripts/install.sh', parameters('artifactsLocationSasToken'))]",
                        "[concat(parameters('artifactsLocation'), '/scripts/azureProviderAndCreds.tf', parameters('artifactsLocationSasToken'))]"
                    ]
                },
                "protectedSettings": {
                    "commandToExecute": "[concat('bash infra.sh && bash install.sh ', variables('installParm1'), variables('installParm2'), variables('installParm3'), variables('installParm4'), ' -k ', listKeys(resourceId('Microsoft.Storage/storageAccounts', variables('stateStorageAccountName')), '2017-10-01').keys[0].value, ' -l ', reference(concat(resourceId('Microsoft.Compute/virtualMachines/', parameters('vmName')),'/providers/Microsoft.ManagedIdentity/Identities/default'),'2015-08-31-PREVIEW').principalId)]"
                }
            },
            "dependsOn": [
                "[resourceId('Microsoft.Authorization/roleAssignments', variables('resourceGuid'))]"
            ]
        }
[snip]
```

### VMにログインし、環境を確認
では出来上がったVMにsshし、いろいろのぞいてみましょう。

```
$ ssh your-vm-public-ip
```

Terraformのバージョンは、現時点で最新の0.11.5が入っています。

```
$ terraform -v
Terraform v0.11.5
```

環境変数ARM_USE_MSIはtrueに設定されています。

```
$ echo $ARM_USE_MSI
true
```

MSIも有効化されています(SystemAssigned)。

```
$ az vm identity show -g tf-msi-poc-ejp-rg -n tfmsipocvm01
{
  "additionalProperties": {},
  "identityIds": null,
  "principalId": "aaaa-aaaa-aaaa-aaaa-aaaa",
  "tenantId": "tttt-tttt-tttt-tttt",
  "type": "SystemAssigned"
}
```

さて、このVMはMSIが使えるようになったわけですが、操作できるリソースのスコープは、このVMが属するリソースグループに限定されてます。新たなリソースグループを作成したい場合は、ロールを付与し、スコープを広げます。~/にtfEnv.shというスクリプトが用意されています。用意されたスクリプトを実行すると、サブスクリプションスコープのContributorがVMに割り当てられます。必要に応じて変更しましょう。

```
$ ls
tfEnv.sh  tfTemplate

$ cat tfEnv.sh
az login
az role assignment create  --assignee "aaaa-aaaa-aaaa-aaaa-aaaa" --role 'b24988ac-6180-42a0-ab88-20f7382dd24c'  --scope /subscriptions/"cccc-cccc-cccc-cccc"

$ . ~/tfEnv.sh
To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code HOGEHOGE to authenticate.
[snip]
{
  "additionalProperties": {},
  "canDelegate": null,
  "id": "/subscriptions/cccc-cccc-cccc-cccc/providers/Microsoft.Authorization/roleAssignments/ffff-ffff-ffff-ffff",
  "name": "ffff-ffff-ffff-ffff",
  "principalId": "aaaa-aaaa-aaaa-aaaa-aaaa",
  "roleDefinitionId": "/subscriptions/cccc-cccc-cccc-cccc/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
  "scope": "/subscriptions/cccc-cccc-cccc-cccc",
  "type": "Microsoft.Authorization/roleAssignments"
}
```

ちなみに、role id "b24988ac-6180-42a0-ab88-20f7382dd24c"はConributorを指します。

tfTemplateというディレクトリも用意されているようです。2つのファイルがあります。

```
$ ls tfTemplate/
azureProviderAndCreds.tf  remoteState.tf
```

azureProviderAndCreds.tfは、tfファイルのテンプレートです。コメントアウトと説明のとおり、MSIを使う場合には、このテンプレートは必要ありません。subscription_idとtenant_idは、VMのプロビジョニング時に環境変数にセットされています。そしてclient_idとclient_secretは、MSIを通じて取得されます。明示的に変えたい時のみ指定しましょう。

```
$ cat tfTemplate/azureProviderAndCreds.tf
#
#
# Provider and credential snippet to add to configurations
# Assumes that there's a terraform.tfvars file with the var values
#
# Uncomment the creds variables if using service principal auth
# Leave them commented to use MSI auth
#
#variable subscription_id {}
#variable tenant_id {}
#variable client_id {}
#variable client_secret {}

provider "azurerm" {
#    subscription_id = "${var.subscription_id}"
#    tenant_id = "${var.tenant_id}"
#    client_id = "${var.client_id}"
#    client_secret = "${var.client_secret}"
}
```

remoteState.tfは、TerraformのstateをAzureのBlob上に置く場合に使います。Blobの[soft delete](https://azure.microsoft.com/en-us/blog/soft-delete-for-azure-storage-blobs-now-in-public-preview/)が使えるようになったこともあり、事件や事故を考慮すると、できればstateはローカルではなくBlobで管理したいところです。

```
$ cat tfTemplate/remoteState.tf
terraform {
 backend "azurerm" {
  storage_account_name = "storestaterandomid"
  container_name       = "terraform-state"
  key                  = "prod.terraform.tfstate"
  access_key           = "KYkCz88z+7yoyoyoiyoyoyoiyoyoyoiyoiTDZRbrwAWIPWD+rU6g=="
  }
}
```

Soft Delete設定は、別途 [az storage blob service-properties delete-policy update](https://docs.microsoft.com/en-us/cli/azure/storage/blob/service-properties/delete-policy?view=azure-cli-latest#az-storage-blob-service-properties-delete-policy-update) コマンドで行ってください。

### プロビジョニングしてみる
ではTerraformを動かしてみましょう。サブディレクトリsampleを作り、そこで作業します。

```
$ mkdir sample
$ cd sample/
```

stateはBlobで管理しましょう。先ほどのremoteState.tfを実行ディレクトリにコピーします。アクセスキーが入っていますので、このディレクトリをコード管理システム配下に置くのであれば、.gitignoreなどで除外をお忘れなく。

```
$ cp ../tfTemplate/remoteState.tf ./
```

ここのキーが残ってしまうのが現時点での課題。ストレージのキー問題は[対応がはじまったので](https://feedback.azure.com/forums/217298-storage/suggestions/14831712-allow-user-based-access-to-blob-containers-for-su)、いずれ解決するはずです。

ではTerraformで作るリソースを書きます。さくっとACI上にnginxコンテナーを作りましょう。

```
$ vim main.tf
resource "azurerm_resource_group" "tf-msi-poc" {
    name     = "tf-msi-poc-aci-wus-rg"
    location = "West US"
}

resource "random_integer" "random_int" {
    min = 100
    max = 999
}

resource "azurerm_container_group" "aci-example" {
    name                = "aci-cg-${random_integer.random_int.result}"
    location            = "${azurerm_resource_group.tf-msi-poc.location}"
    resource_group_name = "${azurerm_resource_group.tf-msi-poc.name}"
    ip_address_type     = "public"
    dns_name_label      = "tomakabe-aci-cg-${random_integer.random_int.result}"
    os_type             = "linux"

    container {
        name    = "nginx"
        image   = "nginx"
        cpu     = "0.5"
        memory  = "1.0"
        port    = "80"
    }
}
```

init、plan、アプラーイ。アプライ王子。

```
$ terraform init
$ terraform plan
$ terraform apply -auto-approve
[snip]
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
```

できたか確認。

```
$ az container show -g tf-msi-poc-aci-wus-rg -n aci-cg-736 -o table
Name        ResourceGroup          ProvisioningState    Image    IP:ports         CPU/Memory       OsType    Location
----------  ---------------------  -------------------  -------  ---------------  ---------------  --------  ----------
aci-cg-736  tf-msi-poc-aci-wus-rg  Succeeded            nginx    13.91.90.117:80  0.5 core/1.0 gb  Linux     westus
$ curl 13.91.90.117
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
[snip]
```

## おまけ
サービスプリンシパルは、アプリに対して権限を付与するために必要な仕組みなのですが、使わなくなった際に消し忘れることが多いです。意識して消さないと、散らかり放題。

MSIの場合、対象のVMを消すとそのプリンシパルも消えます。爽快感ほとばしる。

```
$ az ad sp show --id aaaa-aaaa-aaaa-aaaa-aaaa
Resource 'aaaa-aaaa-aaaa-aaaa-aaaa' does not exist or one of its queried reference-property objects are not present.
```