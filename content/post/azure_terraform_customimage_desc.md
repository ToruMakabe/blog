+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform"]
date = "2018-04-06T18:00:00+09:00"
title = "TerraformでAzure VM/VMSSの最新のカスタムイメージを指定する方法"

+++

## カスタムイメージではlatest指定できない
Azure Marketplaceで提供されているVM/VMSSのイメージは、latest指定により最新のイメージを取得できます。いっぽうでカスタムイメージの場合、同様の属性を管理していないので、できません。

ではVM/VMSSを作成するとき、どうやって最新のカスタムイメージ名を指定すればいいでしょうか。

1. 最新のイメージ名を確認のうえ、手で指定する
2. 自動化パイプラインで、イメージ作成とVM/VMSS作成ステップでイメージ名を共有する

2のケースは、JenkinsでPackerとTerraformを同じジョブで流すケースがわかりやすい。変数BUILD_NUMBERを共有すればいいですね。でもイメージに変更がなく、Terraformだけ流したい時、パイプラインを頭から流してイメージ作成をやり直すのは、無駄なわけです。

## Terraformではイメージ名取得に正規表現とソートが可能
Terraformでは見出しの通り、捗る表現ができます。

イメージを取得するとき、name_regexでイメージ名を引っ張り、sort_descendingを指定すればOK。以下の例は、イメージ名をubuntu1604-xxxxというルールで作ると決めた場合の例です。イメージを作るたびに末尾をインクリメントしてください。ソートはイメージ名全体の[文字列比較](https://github.com/terraform-providers/terraform-provider-azurerm/blob/master/azurerm/data_source_image.go#L164)なので、末尾の番号の決めた桁は埋めること。

ということで降順で最上位、つまり最新のイメージ名を取得できます。

```
data "azurerm_image" "poc" {
  name_regex          = "ubuntu1604-[0-9]*"
  sort_descending     = true
  resource_group_name = "${var.managed_image_resource_group_name}"
}
```

あとはVM/VMSSリソース定義内で、取得したイメージのidを渡します。

```
  storage_profile_image_reference {
    id = "${data.azurerm_image.poc.id}"
  }
```

便利である。