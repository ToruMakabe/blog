+++
Categories = ["Azure"]
Tags = ["Azure", "ARM Template", "Managed Disk"]
date = "2017-03-23T15:00:00+09:00"
title = "Azure Resource Manager テンプレートでManaged Diskを作るときのコツ"

+++

## お伝えしたいこと

* ARMテンプレートのドキュメントが使いやすくなった
* Visual Studio CodeとAzure Resource Manager Toolsを使おう
* ARMテンプレートでManaged Diskを作る時のコツ
* 可用性セットを意識しよう

## ARMテンプレートのドキュメントが使いやすくなった

docs.microsoft.com の整備にともない、ARMテンプレートのドキュメントも[使いやすくなりました](https://azure.microsoft.com/ja-jp/blog/azure-resource-manager-template-reference-now-available/)。ARMテンプレート使いのみなさまは [https://docs.microsoft.com/ja-jp/azure/templates/](https://docs.microsoft.com/ja-jp/azure/templates/) をブックマークして、サクサク調べちゃってください。

## Visual Studio CodeとAzure Resource Manager Toolsを使おう

これがあまり知られてないようなのでアピールしておきます。

![コードアシスト](https://docs.microsoft.com/ja-jp/azure/azure-resource-manager/media/resource-manager-create-first-template/vs-code-show-values.png "コードアシスト")

コードアシストしてくれます。

画面スクロールが必要なほどのJSONをフリーハンドで書けるほど人類は進化していないというのがわたしの見解です。ぜひご活用ください。

[Get VS Code and extension](https://docs.microsoft.com/ja-jp/azure/azure-resource-manager/resource-manager-create-first-template?toc=%2fazure%2ftemplates%2ftoc.json&bc=%2Fazure%2Ftemplates%2Fbreadcrumb%2Ftoc.json#get-vs-code-and-extension)

## ARMテンプレートでManaged Diskを作る時のコツ

Managed Diskが使えるようになって、ARMテンプレートでもストレージアカウントの定義を省略できるようになりました。Managed Diskの実体は内部的にAzureが管理するストレージアカウントに置かれるのですが、ユーザーからは隠蔽されます。

Managed Diskは [Microsoft.Compute/disks](https://docs.microsoft.com/ja-jp/azure/templates/microsoft.compute/disks)  で個別に定義できますが、省略もできます。[Microsoft.Compute/virtualMachines](https://docs.microsoft.com/ja-jp/azure/templates/microsoft.compute/virtualmachines) の中に書いてしまうやり口です。

```
"osDisk": {
  "name": "[concat(variables('vmName'),'-md-os')]",
  "createOption": "FromImage",
  "managedDisk": {
    "storageAccountType": "Standard_LRS"
  },
  "diskSizeGB": 128
}
```

こんな感じで書けます。ポイントはサイズ指定 "diskSizeGB" の位置です。"managedDisk"の下ではありません。おじさんちょっと悩みました。

## 可用性セットを意識しよう

Managed Diskを使う利点のひとつが、可用性セットを意識したディスク配置です。可用性セットに仮想マシンを配置し、かつManaged Diskを使うと、可用性を高めることができます。 

Azureのストレージサービスは、多数のサーバーで構成された分散ストレージで実現されています。そのサーバー群をStorage Unitと呼びます。StampとかClusterと表現されることもあります。Storage Unitは数十のサーバーラック、数百サーバーで構成され、Azureの各リージョンに複数配置されます。

[参考情報:Windows Azure ストレージ: 高可用性と強い一貫性を両立する クラウド ストレージ サービス(PDF)](http://download.microsoft.com/download/C/0/2/C02C4D26-0472-4688-AC13-199EA321135E/23rdACM_SOSP_WindowsAzureStorage_201110_jpn.pdf)

可用性セットは、電源とネットワークを共有するグループである"障害ドメイン(FD: Fault Domain)"を意識して仮想マシンを分散配置する設定です。そして、可用性セットに配置した仮想マシンに割り当てたManaged Diskは、Storage Unitを分散するように配置されます。


![Unmanaged vs Managed](https://msdnshared.blob.core.windows.net/media/2017/03/92.jpg "Unmanaged vs Managed")

すなわち、Storage Unitの障害に耐えることができます。Storage Unitは非常に可用性高く設計されており、長期に運用されてきた実績もあるのですが、ダウンする可能性はゼロではありません。可用性セットとManaged Diskの組み合わせは、可用性を追求したいシステムでは、おすすめです。

さて、この場合の可用性セット定義ですが、以下のように書きます。

```
{
  "type": "Microsoft.Compute/availabilitySets",
  "name": "AvSet01",
  "apiVersion": "2016-04-30-preview",
  "location": "[resourceGroup().location]",
  "properties": {
    "managed": true,
    "platformFaultDomainCount": 2,
    "platformUpdateDomainCount": 5
  }
},
```

[Microsoft.Compute/availabilitySets](https://docs.microsoft.com/ja-jp/azure/templates/microsoft.compute/availabilitysets) を読むと、Managed Diskを使う場合は"propaties"の"managed"をtrueにすべし、とあります。なるほど。

そしてポイントです。合わせて"platformFaultDomainCount"を指定してください。managedにする場合は必須パラメータです。

なお、リージョンによって配備されているStorage Unit数には違いがあるのでご注意を。例えば東日本リージョンは2です。3のリージョンもあります。それに合わせて可用性セットの障害ドメイン数を指定します。


[Azure IaaS VM ディスクと Premium 管理ディスクおよび非管理ディスクについてよく寄せられる質問](https://docs.microsoft.com/ja-jp/azure/storage/storage-faq-for-disks)

```
Managed Disks を使用する可用性セットでサポートされる障害ドメイン数はいくつですか?

Managed Disks を使用する可用性セットでサポートされる障害ドメイン数は 2 または 3 です。これは、配置されているリージョンによって異なります。
```