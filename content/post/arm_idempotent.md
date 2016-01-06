+++
Categories = ["Azure"]
Tags = ["Azure", "ARM"]
date = "2016-01-06T00:16:00+09:00"
title = "Azure ARM Templateによるデプロイと冪等性"

+++

## 宣言的に、冪等に
ここ数年で生まれたデプロイメント手法、ツールは数多くありますが、似たような特徴があります。それは「より宣言的に、冪等に」です。これまで可読性や再利用性を犠牲にしたシェル芸になりがちだったデプロイの世界。それがいま、あるべき姿を定義しその状態に収束させるように、また、何度ツールを実行しても同じ結果が得られるように変わってきています。

さて、そんな時流に飛び込んできたデプロイ手法があります。AzureのARM(Azure Resource Manager) Templateによるデプロイです。ARMはAzureのリソース管理の仕組みですが、そのARMに対し、構成を宣言的に書いたJSONを食わせて環境を構築する手法です。Azureの標準機能として、提供されています。

### [Azure リソース マネージャーの概要](https://azure.microsoft.com/ja-jp/documentation/articles/resource-group-overview/)
> "ソリューションを開発のライフサイクル全体で繰り返しデプロイできます。また、常にリソースが一貫した状態でデプロイされます"

> "宣言型のテンプレートを利用し、デプロイメントを定義できます"

冪等と言い切ってはいませんが、目的は似ています。

なるほど、期待十分。ではあるのですが、冪等性の実現は簡単ではありません。たとえばChefやAnsibleも、冪等性はリソースやモジュール側で考慮する必要があります。多様なリソースの違いを吸収しなければいけないので、仕方ありません。魔法じゃないです。その辺を理解して使わないと、ハマります。

残念ながらARMは成長が著しく、情報が多くありません。そこで、今回は実行結果を元に、冪等さ加減を理解していきましょう。

## 増分デプロイと完全デプロイ
まず、デプロイのコマンド例を見ていきましょう。今回はPowerShellを使いますが、Mac/Linux/Winで使える[クロスプラットフォームCLI](https://github.com/Azure/azure-xplat-cli)もあります。

    PS C:\> New-AzureRmResourceGroupDeployment -ResourceGroupName YourRGName -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json
    
ワンライナーです。これだけで環境ができあがります。-TemplateFileでリソース定義を記述したJSONファイルを指定します。また、-TemplateParameterFileにパラメータを外だしできます。

今回は冪等さがテーマであるため詳細は省きます。関心のあるかたは、別途[ドキュメント](https://azure.microsoft.com/ja-jp/documentation/articles/resource-group-template-deploy/)で確認してください。

さて、ワンライナーで環境ができあがるわけですが、その後が重要です。環境変更の際にJSONで定義を変更し、同じコマンドを再投入したとしても、破たんなく使えなければ冪等とは言えません。

コマンド投入には2つのモードがあります。増分(Incremental)と完全(Complete)です。まずは増分から見ていきましょう。

>・リソース グループに存在するが、テンプレートに指定されていないリソースを変更せず、そのまま残します

>・テンプレートに指定されているが、リソース グループに存在しないリソースを追加します 

>・テンプレートに定義されている同じ条件でリソース グループに存在するリソースを再プロビジョニングしません

すでに存在するリソースには手を入れず、JSONへ新たに追加されたリソースのみを追加します。

いっぽうで、完全モードです。

>・リソース グループに存在するが、テンプレートに指定されていないリソースを削除します

>・テンプレートに指定されているが、リソース グループに存在しないリソースを追加します 

>・テンプレートに定義されている同じ条件でリソース グループに存在するリソースを再プロビジョニングしません

2、3番目は増分と同じです。1番目が違います。JSONから定義を消されたリソースを削除するかどうかが、ポイントです。完全モードはスッキリするけどリスクも高そう、そんな印象を受けるのはわたしだけではないでしょう。

## 動きをつかむ
では動きを見ていきましょう。テンプレートはGithubに公開されている[Very simple deployment of an Linux VM](https://github.com/Azure/azure-quickstart-templates/tree/master/101-vm-simple-linux)を使います。詳細は説明しませんので、読み進める前にリソース定義テンプレートファイル(azuredeploy.json)を[リンク先](https://github.com/Azure/azure-quickstart-templates/blob/master/101-vm-simple-linux/azuredeploy.json)でざっと確認してください。

パラメータファイル(azuredeploy.parameters.json)は以下とします。

    {
      "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "adminUsername": {
          "value": "azureUser"
        },
        "adminPassword": {
          "value": "password1234!"
        },
        "dnsLabelPrefix": {
          "value": "armpocps"
        },
        "ubuntuOSVersion": {
          "value": "14.04.2-LTS"
        }    
      }
    }

まず、1回目の実行です。リソースグループ "ARMEval"に対しデプロイします。このリソースグループは前もって作っておいた空の箱です。

    PS C:\Workspace> New-AzureRmResourceGroupDeployment -ResourceGroupName ARMEval -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json 

    DeploymentName    : azuredeploy
    ResourceGroupName : ARMEval
    ProvisioningState : Succeeded
    Timestamp         : 2016/01/04 11:46:41
    Mode              : Incremental
    TemplateLink      :
    Parameters        :
                    Name             Type                       Value
                    ===============  =========================  ==========
                    adminUsername    String                     azureUser
                    adminPassword    SecureString
                    dnsLabelPrefix   String                     armpocps
                    ubuntuOSVersion  String                     14.04.2-LTS

    Outputs           :

できあがりです。空のリソースグループ にLinux VM、ストレージ、仮想ネットワーク、パブリックIPなどがデプロイされました。Modeを指定しない場合は増分(Incremental)となります。

この環境にじわじわと変更を入れていきましょう。まずはazuredeploy.parameter.json上のパラメータ、DNS名のPrefix(dnsLabelPrefix)をarmpocps -> armpocps2と変えます。

    "dnsLabelPrefix": {
      "value": "armpocps2"
    },

では再投入です。パラメータファイルの内容は変えましたが、コマンドは同じです。

    PS C:\Workspace> New-AzureRmResourceGroupDeployment -ResourceGroupName ARMEval -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json 
    [snip]
    Parameters        :
                    Name             Type                       Value
                    ===============  =========================  ==========
                    adminUsername    String                     azureUser
                    adminPassword    SecureString
                    dnsLabelPrefix   String                     armpocps2
                    ubuntuOSVersion  String                     14.04.2-LTS

変更内容の確認です。
    
    PS C:\Workspace> Get-AzureRmPublicIpAddress
    [snip]
    DnsSettings              : {
                                 "DomainNameLabel": "armpocps2",
                                 "Fqdn": "armpocps2.japanwest.cloudapp.azure.com"
                               }

問題なく変わっていますね。冪等チックです。この例ではシンプルにDNS名のPrefixを変えましたが、VMインスタンス数やsubnet名を変えたりもできます。関心のある方は[ドキュメント](https://gallery.technet.microsoft.com/Cloud-Consistency-with-0b79b775)を。

増分モードによる変更は期待できそうです。が、さて、ここからが探検です。リソース削除が可能な完全モードを試してみましょう。
リソース定義ファイル(azuredeploy.json)から、大胆にVMの定義を削ってみます。下記リソースをファイルからごっそり消します。

    {
      "apiVersion": "[variables('apiVersion')]",
      "type": "Microsoft.Compute/virtualMachines",
      "name": "[variables('vmName')]",
    [snip]

では、完全モード "-Mode complete"付きでコマンドを再投入します。

    PS C:\Workspace> New-AzureRmResourceGroupDeployment -ResourceGroupName ARMEval -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json  -Mode complete

    確認
    Are you sure you want to use the complete deployment mode? Resources in the resource group 'ARMEval' which are not included in the template will be deleted.
    [Y] はい(Y)  [N] いいえ(N)  [S] 中断(S)  [?] ヘルプ (既定値は "Y"): Y
    
    DeploymentName    : azuredeploy
    ResourceGroupName : ARMEval
    ProvisioningState : Succeeded
    Timestamp         : 2016/01/04 12:01:00
    Mode              : Complete
    TemplateLink      :
    Parameters        :
                    Name             Type                       Value
                    ===============  =========================  ==========
                    adminUsername    String                     azureUser
                    adminPassword    SecureString
                    dnsLabelPrefix   String                     armpocps2
                    ubuntuOSVersion  String                     14.04.2-LTS

    Outputs           :

あっさり完了しました。本当にVMが消えているが確認します。出力が冗長ですがご容赦ください。

    PS C:\Workspace> Find-AzureRmResource -ResourceGroupNameContains ARMEval
    
    Name              : myPublicIP
    ResourceId        :     /subscriptions/your-subscription-id/resourceGroups/ARMEval/providers/Microsoft.Network/publicIPAddresses/myPublicIP
    ResourceName      : myPublicIP
    ResourceType      : Microsoft.Network/publicIPAddresses
    ResourceGroupName : ARMEval
    Location          : japanwest
    SubscriptionId    : your-subscription-id
    
    Name              : myVMNic
    ResourceId        : /subscriptions/your-subscription-id/resourceGroups/ARMEval/providers/Microsoft.Network/networkInterfaces/myVMNic
    ResourceName      : myVMNic
    ResourceType      : Microsoft.Network/networkInterfaces
    ResourceGroupName : ARMEval
    Location          : japanwest
    SubscriptionId    : your-subscription-id
    
    Name              : MyVNET
    ResourceId        : /subscriptions/your-subscription-id/resourceGroups/ARMEval/providers/Microsoft.Network/virtualNetworks/MyVNET
    ResourceName      : MyVNET
    ResourceType      : Microsoft.Network/virtualNetworks
    ResourceGroupName : ARMEval
    Location          : japanwest
    SubscriptionId    : your-subscription-id
    
    Name              : yourstorageaccount
    ResourceId        : /subscriptions/your-subscription-id/resourceGroups/ARMEval/providers/Microsoft.Storage/storageAccounts/yourstorageaccount
    ResourceName      : yourstorageaccount
    ResourceType      : Microsoft.Storage/storageAccounts
    ResourceGroupName : ARMEval
    Location          : japanwest
    SubscriptionId    : your-subscription-id
    Tags              : {}

VMだけが消えています。定義からリソースがなくなれば、存在するリソースも消す、これが完全モードです。

さらに検証。冪等さを求めるのであれば、またリソース定義にVMを加えて再投入したら、涼しい顔で復活してほしい。先ほどazuredeploy.jsonから消したVMリソース定義を、そのまま書き戻して再投入してみます。

    PS C:\Workspace> New-AzureRmResourceGroupDeployment -ResourceGroupName ARMEval -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json  -Mode complete

    確認
    Are you sure you want to use the complete deployment mode? Resources in the resource group 'ARMEval' which are not included in the template will be deleted.
    [Y] はい(Y)  [N] いいえ(N)  [S] 中断(S)  [?] ヘルプ (既定値は "Y"): Y

    New-AzureRmResourceGroupDeployment : 21:05:52 - Resource Microsoft.Compute/virtualMachines 'MyUbuntuVM' failed with message 'The resource operation completed with terminal provisioning state 'Failed'.'
    [snip]
    New-AzureRmResourceGroupDeployment : 21:05:52 - One or more errors occurred while preparing VM disks. See disk instance view for details.

残念ながら失敗しました。どうやらdiskまわりのエラーが発生したようです。

これは、完全モードでのリソース削除の仕様が原因です。ARMは該当のVMリソースは消すのですが、VMが格納されているストレージを削除しません。リソース作成時は依存関係が考慮されますが、削除時は異なります。

試しにストレージを消して再実行してみましょう。

    PS C:\Workspace> New-AzureRmResourceGroupDeployment -ResourceGroupName ARMEval -TemplateFile .\azuredeploy.json -TemplateParameterFile .\azuredeploy.parameters.json  -Mode complete

    [snip]
    ProvisioningState : Succeeded

定義通りの環境になりました。依存関係をたどって消してほしいのが人情ですが、残したほうがいいケースもあるので、今後の改善を期待しましょう。

## 使い方
冪等であると言い切れないものの、リソース定義と実行モードを理解したうえで使えば有用。ただ、完全モードによる削除は使い方が難しい。現状ではそんな印象です。

そこで、ARM Templateをデプロイに組み込む際、ARMによるデプロイはBootstrap用途に限定し、より構成頻度が高いConfiguration用途には、冪等性を持った別のツールを組み合わせるのが現実解と考えます。

Bootstrap用途では、プラットフォームの提供機能を使ったほうが、機能も多いし最適化されています。Azureで今後この層を担当していくのはARMです。そして、この用途ではChefやAnsibleなど汎用ツールに物足りなさがあります。

また、Bootstrapは1回切りであるケースが多いので、失敗したらリソースグループをばっさり消して再作成する、と割り切りやすいです。それならば冪等でなくともいいでしょう。

長くなったので、デプロイツールの組み合わせについては、あたらめて書きたいと思います。

参考: [インフラ系技術の流れ Bootstrapping/Configuration/Orchestration](http://mizzy.org/blog/2013/10/29/1/)