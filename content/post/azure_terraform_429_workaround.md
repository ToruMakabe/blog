+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform", "ARM"]
date = "2016-03-23T13:00:00+09:00"
title = "Azure & Terraform エラーコード429の対処法"

+++

## Terraformer増加に備えて
2016/3/21にリリースされたTerraform v0.6.14で、Azure Resource Manager ProviderのリソースにVMとテンプレートデプロイが[追加](https://github.com/hashicorp/terraform/blob/v0.6.14/CHANGELOG.md)されました。待っていた人も多いのではないでしょうか。

追って[Hashicorp認定パートナー](https://www.hashicorp.com/partners.html#sipart)のクリエーションラインさんから導入・サポートサービスが[アナウンス](http://www.creationline.com/lab/13268)されましたし、今後AzureをTerraformでコントロールしようという需要は増えそうです。

## エラーコード429
さて、TerraformでAzureをいじっていると、下記のようなエラーに出くわすことがあります。

    Error applying plan:

    1 error(s) occurred:
    azurerm_virtual_network.vnet1: autorest:DoErrorUnlessStatusCode 429 PUT https://management.azure.com/subscriptions/my_subscription_id/resourceGroups/mygroup/providers/Microsoft.Network/virtualnetworks/vnet1?api-version=2015-06-15 failed with 429

autorestがステータスコード429をキャッチしました。[RFC上で429は](https://tools.ietf.org/html/rfc6585#section-4)"Too many requests"です。何かが多すぎたようです。

## 対処法
**もう一度applyしてください**

冪等性最高。冪等性なんていらない、という人もいますが、こういうときはありがたい。

## 背景
エラーになった背景ですが、2つの可能性があります。

1. APIリクエスト数上限に達した
2. リソースの作成や更新に時間がかかっており、Azure側で処理を中断した

### 1. APIリクエスト数上限に達した
Azure Resource Manager APIには時間当たりのリクエスト数制限があります。読み取り 15,000/時、書き込み1,200/時です。

**[Azure サブスクリプションとサービスの制限、クォータ、制約](https://azure.microsoft.com/ja-jp/documentation/articles/azure-subscription-service-limits/)**

Terraformは扱うリソースごとにAPIをコールするので、数が多い環境で作って壊してをやると、この上限にひっかかる可能性があります。

長期的な対処として、Terraformにリトライ/Exponential Backoffロジックなどを実装してもらうのがいいのか、このままユーザ側でシンプルにリトライすべきか、悩ましいところです。

ひとまずプロダクトの方針は確認したいので、Issueに質問を[あげておきました](https://github.com/hashicorp/terraform/issues/5704)。

### 2. リソースの作成や更新に時間がかかっており、Azure側で処理を中断した
Terraform側ではエラーコードで判断するしかありませんが、Azureの監査ログで詳細が確認できます。

わたしが経験したエラーの中に、こんなものがありました。

    Cannot proceed with operation since resource /subscriptions/GUID/resourceGroups/xxxx/providers/Microsoft.Network/networkSecurityGroups/yyy allocated to resource /subscriptions/GUID/resourceGroups/***/providers/Microsoft.Network/virtualNetworks/yyy is not in Succeeded state. Resource is in Updating state and the last operation that updated/is updating the resource is PutSecurityRuleOperation. 
    
Too many requestsというよりは、リソースのアップデートが終わってないので先に進めない、という内容です。

Too many requestsをどう解釈するかにもよりますが、ちょっと混乱しますね。この問題はFeedbackとして[あがっています](https://feedback.azure.com/forums/34192--general-feedback/suggestions/13069563-better-http-status-code-instead-of-429)。


でも安心してください。**もう一度applyしてください**。
