+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform", "ARM"]
date = "2016-02-27T12:30:00+09:00"
title = "TerraformをAzure ARMで使う時の認証"

+++

## 高まってまいりました
全国10,000人のTerraformファンのみなさま、こんにちは。applyしてますか。

Terraformのマイナーバージョンアップのたびに、[Azure Resource Manager Providerのリソース](https://www.terraform.io/docs/providers/azurerm/index.html)が追加されているので、ぼちぼちClassic(Service Management)からの移行を考えよう、という人もいるのでは。VMリソースが追加されたら、いよいよ、ですかね。

そこで、Classicとは認証方式が変わっているので、ご注意を、という話です。

## client_id/client_secret って何よ
以下がARM向けのProvider設定です。

    # Configure the Azure Resource Manager Provider
    provider "azurerm" {
      subscription_id = "..."
      client_id       = "..."
      client_secret   = "..."
      tenant_id       = "..."
    }
    

subscription_idは、いつものあれ。tenant_idは普段使わないけどどこかで見た気がする。でも、*client_id/client_secret って何よ*。ためしにポータルログインで使うID/パスワード指定したら、盛大にコケた。

## サービスプリンシパルを使おう
Terraformをアプリケーションとして登録し、そのサービスプリンシパルを作成し権限を付与すると、使えるようになります。

["Azure リソース マネージャーでのサービス プリンシパルの認証"](https://azure.microsoft.com/ja-jp/documentation/articles/resource-group-authenticate-service-principal/#--azure-cli)

以下、Azure CLIでの実行結果をのせておきます。WindowsでもMacでもLinuxでも手順は同じです。

まずは、Terraformをアプリとして登録します。--identifier-urisはユニークにしなければいけません。

    $ azure ad app create --name "My Terraform" --home-page "http://tftest.makabe.info" --identifier-uris "http://tftest.makabe.info" --password pAssw0rd%
    info:    Executing command ad app create
    + Creating application My Terraform
    data:    AppId:                   AppId-AppId-AppId-AppId-AppId
    data:    ObjectId:                AppObjId-AppObjId-AppObjId-AppObjId
    data:    DisplayName:             My Terraform
    data:    IdentifierUris:          0=http://tftest.makabe.me
    data:    ReplyUrls:
    data:    AvailableToOtherTenants:  False
    data:    AppPermissions:
    data:                             claimValue:  user_impersonation
    data:                             description:  Allow the application to access My Terraform on behalf of the signed-in user.
    data:                             directAccessGrantTypes:
    data:                             displayName:  Access My Terraform
    data:                             impersonationAccessGrantTypes:  impersonated=User, impersonator=Application
    data:                             isDisabled:
    data:                             origin:  Application
    data:                             permissionId:  AppPermID-AppPermID-AppPermID-AppPermID
    data:                             resourceScopeType:  Personal
    data:                             userConsentDescription:  Allow the application to access My Terraform on your behalf.
    data:                             userConsentDisplayName:  Access My Terraform
    data:                             lang:
    info:    ad app create command OK

次にサービスプリンシパルを作ります。AppIdは先ほどアプリを登録した際に生成されたものです。

    $ azure ad sp create AppId-AppId-AppId-AppId-AppId
    info:    Executing command ad sp create
    + Creating service principal for application AppId-AppId-AppId-AppId-AppId
    data:    Object Id:               SpObjId-SpObjId-SpObjId-SpObjId
    data:    Display Name:            My Terraform
    data:    Service Principal Names:
    data:                             AppId-AppId-AppId-AppId-AppId
    data:                             http://tftest.makabe.me
    info:    ad sp create command OK
    
サービスプリンシパルの役割を設定します。--objectIdは、サービスプリンシパルのObject Idなのでご注意を。アプリのObject Idではありません。

この例では、サブスクリプションのContributorとして位置づけました。権限設定は慎重に。

    $ azure role assignment create --objectId SpObjId-SpObjId-SpObjId-SpObjId-SpObjId -o Contributor -c /subscriptions/SubId-SubId-SubId-SubId-SubId/
    info:    Executing command role assignment create
    + Finding role with specified name
    /data:    RoleAssignmentId     : /subscriptions/SubId-SubId-SubId-SubId-SubId/providers/Microsoft.Authorization/roleAssignments/RoleAsId-RoleAsId-RoleAsId-RoleAsId
    data:    RoleDefinitionName   : Contributor
    data:    RoleDefinitionId     : RoleDefId-RoleDefId-RoleDefId-RoleDefId-RoleDefId
    data:    Scope                : /subscriptions/SubId-SubId-SubId-SubId-SubId
    data:    Display Name         : My Terraform
    data:    SignInName           :
    data:    ObjectId             : SpObjId-SpObjId-SpObjId-SpObjId-SpObjId
    data:    ObjectType           : ServicePrincipal
    data:
    +
    info:    role assignment create command OK
    
サービスプリンシパルまわりの設定は以上です。

テナントIDを確認しておきましょう。

    $ azure account list --json
    [
      {
        "id": "SubId-SubId-SubId-SubId-SubId",
        "name": "Your Subscription Name",
        "user": {
          "name": "abc@microsoft.com",
          "type": "user"
        },
        "tenantId": "TenantId-TenantId-TenantId-TenantId-TenantId",
        "state": "Enabled",
        "isDefault": true,
        "registeredProviders": [],
        "environmentName": "AzureCloud"
      }
    ]
    
 これでようやく.tfファイルが書けます。さくっとリソースグループでも作ってみましょう。
 
    # Configure the Azure Resource Manager Provider
    provider "azurerm" {
      subscription_id = "SubId-SubId-SubId-SubId-SubId"
      client_id       = "AppId-AppId-AppId-AppId-AppId"
      client_secret   = "pAssw0rd%"
      tenant_id       = "TenantId-TenantId-TenantId-TenantId-TenantId"
    }
    
    # Create a resource group
    resource "azurerm_resource_group" "test" {
        name     = "test"
        location = "Japan West"
    }
    
appy。もちろんplanしましたよ。

    $ terraform apply
    azurerm_resource_group.test: Creating...
      location: "" => "japanwest"
      name:     "" => "test"
    azurerm_resource_group.test: Creation complete
    
    Apply complete! Resources: 1 added, 0 changed, 0 destroyed.  
    
これで、ARM認証難民がうまれませんように。