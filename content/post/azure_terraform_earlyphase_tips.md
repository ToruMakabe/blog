+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform", "ARM"]
date = "2016-03-25T22:50:00+09:00"
title = "Azure & Terraform Tips (ARM対応 2016春版)"

+++

## 俺の屍を越えていけ
今週リリースされたTerraform v0.6.14で、Azure Resource Manager ProviderのリソースにVMとテンプレートデプロイが[追加](https://github.com/hashicorp/terraform/blob/v0.6.14/CHANGELOG.md)されました。この週末お楽しみ、という人も多いかもしれません。

小生、v0.6.14以前から触っていたこともあり、土地勘があります。そこで現時点でのTipsをいくつかご紹介します。

## この3つは触る前から意識しよう
1. ARMテンプレートリソースは分離して使う
2. リソース競合したら依存関係を定義する
3. 公開鍵認証SSH指定でエラーが出ても驚かない

## 1. ARMテンプレートリソースは分離して使う
v0.6.14で、リソース["azurerm_template_deployment"](https://www.terraform.io/docs/providers/azurerm/r/template_deployment.html)が追加されました。なんとARMテンプレートを、Terraformの定義ファイル内にインラインで書けます。

でも、現時点の実装では、おすすめしません。

### ARMテンプレートのデプロイ機能とTerraformで作ったリソースが不整合を起こす
避けるべきなのは"Complete(完全)"モードでのARMテンプレートデプロイです。なぜなら完全モードでは、ARM リソースマネージャーは次の動きをするからです。

**[リソース グループに存在するが、テンプレートに指定されていないリソースを削除します](https://azure.microsoft.com/ja-jp/documentation/articles/resource-group-template-deploy/)**
  
つまり、ARMテンプレートで作ったリソース以外、Terraform担当部分を消しにいきます。恐怖! デプロイ vs デプロイ!!。リソースグループを分ければ回避できますが、リスク高めです。
  
### タイムアウトしがち
それでもTerraformの外でARMテンプレートデプロイは継続します。成功すれば結果オーライですが...Terraform上はエラーが残ります。「ああそれ無視していいよ」ではあるのですが、[割れ窓理論](https://ja.wikipedia.org/wiki/%E5%89%B2%E3%82%8C%E7%AA%93%E7%90%86%E8%AB%96)的によろしくないです。
  
### せっかくのリソースグラフを活用できない
Terraformはグラフ構造で賢くリソース間の依存関係を管理し、整合性を維持しています。サクサク apply & destroyできるのもそれのおかげです。ARMテンプレートでデプロイしたリソースはそれに入れられないので、もったいないです。
  
### 読みづらい
Terraform DSLにJSONが混ざって読みにくいです。Terraform DSLを使わない手もありますが、それでいいのかという話です。  


それでも"terraformコマンドに操作を統一したい"など、どうしても使いたい人は、ARMテンプレート実行部は管理も実行も分離した方がいいと思います。

## 2. リソース競合したら依存関係を定義する
Terraformはリソース間の依存関係を明示する必要がありません。ですが、行き届かないこともあります。その場合は["depends_on"](https://www.terraform.io/intro/getting-started/dependencies.html)で明示してあげましょう。

例えば、[以前のエントリ](http://torumakabe.github.io/post/azure_terraform_429_workaround/)で紹介した下記の問題。

    Error applying plan:

    1 error(s) occurred:
    azurerm_virtual_network.vnet1: autorest:DoErrorUnlessStatusCode 429 PUT https://management.azure.com/subscriptions/my_subscription_id/resourceGroups/mygroup/providers/Microsoft.Network/virtualnetworks/vnet1?api-version=2015-06-15 failed with 429


    Cannot proceed with operation since resource /subscriptions/GUID/resourceGroups/xxxx/providers/Microsoft.Network/networkSecurityGroups/yyy allocated to resource /subscriptions/GUID/resourceGroups/***/providers/Microsoft.Network/virtualNetworks/yyy is not in Succeeded state. Resource is in Updating state and the last operation that updated/is updating the resource is PutSecurityRuleOperation. 

HTTPステータスコード429(Too many requests)が返ってきているのでわかりにくいですが、実態はセキュリティーグループリソースの取り合いです。

* サブネットリソース作成側: サブネットを新規作成し、セキュリティーグループを紐付けたい
* セキュリティーグループルール作成側: ルールをセキュリティーグループに登録したい(更新処理)

この2つが並行してセキュリティーグループを取り合うので、高確率でエラーになります。セキュリティーグループルールはリソースの新規作成でなく、セキュリティーグループの更新処理であるため「リソースを**作成したら/存在したら**次にすすむ」というTerraformのグラフでうまく表現できないようです。

そのような場合、明示的に依存関係を"depends_on"で定義します。

    # Create a frontend subnet
    # "depends_on" arg is a workaround to avoid conflict with updating NSG rules 
    resource "azurerm_subnet" "frontend" {
        name = "frontend"
        resource_group_name = "${var.resource_group_name}"
        virtual_network_name = "${azurerm_virtual_network.vnet1.name}"
        address_prefix = "${var.vnet1_frontend_address_prefix}"
        network_security_group_id = "${azurerm_network_security_group.frontend.id}"
        depends_on = [
            "azurerm_network_security_rule.fe_web80",
            "azurerm_network_security_rule.fe_web443",
            "azurerm_network_security_rule.fe_ssh"
        ]
    }
    
これでサブネット作成処理は、セキュリティーグループルール登録完了まで、作成処理開始を待ちます。美しくないですが、当面の回避策です。

## 3. 公開鍵認証SSH指定でエラーが出ても驚かない

TerraformはLinux VMの定義で、公開鍵認証SSHを指定できます。こんな感じで。

    os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path = "/home/${var.adminuser}/.ssh/authorized_keys"
            key_data = "${file("/Users/you/.ssh/yourkey.pem")}"
        }
    }

が、エラーが返ってきます。

    [DEBUG] Error setting Virtual Machine Storage OS Profile Linux Configuration: &errors.errorString{s:"Invalid address to set: []string{\"os_profile_linux_config\", \"12345678\", \"ssh_keys\"}"}

残念ながら、Terraformが使っているAzure SDK(Golang)のバグです。

妥当性チェックのエラーで、実際にはキーの登録はできているようです。私は何度か試行してすべて公開鍵SSHログインに成功しています。

[Issueとして認識](https://github.com/hashicorp/terraform/issues/5793)されていますので、修正を待ちましょう。
