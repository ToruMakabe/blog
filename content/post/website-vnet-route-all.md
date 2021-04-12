+++
Categories = ["Azure"]
Tags = ["Azure","App Service","Network"]
date = "2021-04-12T13:30:00+09:00"
title = "Azure App Service WEBSITE_VNET_ROUTE_ALLの設定効果を確認する"

+++

## 何の話か

App ServiceのリージョンVNet統合をした場合、すべての送信トラフィックをVNetに向ける["WEBSITE_VNET_ROUTE_ALL = 1"](https://docs.microsoft.com/ja-jp/azure/app-service/web-sites-integrate-with-vnet#regional-vnet-integration)設定が可能です。すこぶる便利な反面、設定ひとつでルーティングがごそっと変わってしまう気持ち悪さは否めません。そこで、設定することでどのような効果があるのか、実際にインターフェースやルートの設定を見て、理解しておきましょう。ドキュメントを読めばだいたい想像できるのですが、トラブルシューティングの際に念のためルートを確認したいなんてこともあるでしょうから、知っておいて損はありません。

## 確認環境と手法

App Service (Linux/.NET Core 3.1)のアプリコンテナーへ[ssh](https://docs.microsoft.com/ja-jp/azure/app-service/configure-linux-open-ssh-session)し、インターフェースやルートを確認します。

1. VNet統合なし
2. VNet統合あり
3. VNet統合あり(WEBSITE_VNET_ROUTE_ALL = 1)

この流れで、設定の効果を見ていきましょう。

## VNet統合なし

まずは、IPアドレスとインターフェースの設定を確認します。

```
root@96d38124b1f4:~/site/wwwroot# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
34: eth0@if35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:ac:10:02:02 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.16.2.2/24 brd 172.16.2.255 scope global eth0
       valid_lft forever preferred_lft forever
```

ループバックの他に、1つのインターフェース(eth0)があります。では、ルートはどうでしょうか。

```
root@96d38124b1f4:~/site/wwwroot# ip r
default via 172.16.2.1 dev eth0
172.16.2.0/24 dev eth0 proto kernel scope link src 172.16.2.2
```

すべての送信トラフィックは、eth0から送出されます。その先には、App Serviceのマルチテナントネットワークがあります。Azure内のネットワークはオーバレイされているので、コンテナーのインターフェイスに割り当てられたアドレスの意味はあまり気にせず、識別子としてとらえてください。

## VNet統合あり

VNet"vnet-default"をApp Serviceと統合します。以降、azコマンドはApp Serviceアプリコンテナーの中ではなく、別途Azure管理APIに接続できる環境で実行しています。

VNetのアドレス空間を確認しておきます。

```
% az network vnet show --ids "/subscriptions/mysubscription/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-default" -o json --query addressSpace
{
  "addressPrefixes": [
    "10.0.0.0/16"
  ]
}
```

次にVNet "vnet-default"にあるサブネット"snet-appservice-integration"をApp Serviceと統合します。サービスエンドポイントを使うとルーティングに影響するため、サンプルとしてAzure SQL Databaseをサービス登録しておきます。

以下は統合後のサブネットの、関連パラメータの状態です。

```
% az network vnet subnet show -g rg-test --vnet-name vnet-default -n snet-appservice-integration -o json --query "{service
AssociationLinks:serviceAssociationLinks, serviceEndpoints:serviceEndpoints}"
{
  "serviceAssociationLinks": [
    {
      "allowDelete": false,
      "etag": "W/\"hoge-hoge-fuga-fuga\"",
      "id": "/subscriptions/mysubscription/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-default/subnets/snet-appservice-integration/serviceAssociationLinks/AppServiceLink",
      "link": "/subscriptions/mysubscription/resourceGroups/rg-test/providers/Microsoft.Web/serverfarms/plan-test",
      "linkedResourceType": "Microsoft.Web/serverfarms",
      "locations": [],
      "name": "AppServiceLink",
      "provisioningState": "Succeeded",
      "resourceGroup": "rg-test",
      "type": "Microsoft.Network/virtualNetworks/subnets/serviceAssociationLinks"
    }
  ],
  "serviceEndpoints": [
    {
      "locations": [
        "japaneast"
      ],
      "provisioningState": "Succeeded",
      "service": "Microsoft.Sql"
    }
  ]
}
```

ではコンテナを再起動し、アプリコンテナーの中からネットワーク設定を確認してみましょう。まずはIPアドレスとインターフェースから。

```
root@59e822064224:~/site/wwwroot# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
3: eth0@if51: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 1e:60:39:43:eb:4a brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 169.254.129.2/24 brd 169.254.129.255 scope global eth0
       valid_lft forever preferred_lft forever
5: vnet0g85jrhr4@if4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether d6:26:fe:de:c1:01 brd ff:ff:ff:ff:ff:ff link-netnsid 1
    inet 169.254.254.2/24 brd 169.254.254.255 scope global vnet0g85jrhr4
       valid_lft forever preferred_lft forever
```

eth0に加え、VNet向けのインターフェース(vnet0g85jrhr4)が生えました。では、ルートはどうでしょうか。

```
root@59e822064224:~/site/wwwroot# ip r
default via 169.254.129.1 dev eth0 mtu 1500
10.0.0.0/16 via 169.254.254.1 dev vnet0g85jrhr4 proto static
10.0.0.0/8 via 169.254.254.1 dev vnet0g85jrhr4 proto static
13.78.61.196 via 169.254.254.1 dev vnet0g85jrhr4 proto static
13.78.104.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
13.78.104.32/29 via 169.254.254.1 dev vnet0g85jrhr4 proto static
13.78.105.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
13.78.121.203 via 169.254.254.1 dev vnet0g85jrhr4 proto static
20.191.165.160/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
20.191.165.192/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
20.191.166.0/26 via 169.254.254.1 dev vnet0g85jrhr4 proto static
23.102.69.95 via 169.254.254.1 dev vnet0g85jrhr4 proto static
23.102.71.13 via 169.254.254.1 dev vnet0g85jrhr4 proto static
23.102.74.190 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.184.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.184.32/29 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.185.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.192.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.192.32/29 via 169.254.254.1 dev vnet0g85jrhr4 proto static
40.79.193.0/27 via 169.254.254.1 dev vnet0g85jrhr4 proto static
52.185.152.149 via 169.254.254.1 dev vnet0g85jrhr4 proto static
52.243.32.19 via 169.254.254.1 dev vnet0g85jrhr4 proto static
52.243.43.186 via 169.254.254.1 dev vnet0g85jrhr4 proto static
104.41.168.103 via 169.254.254.1 dev vnet0g85jrhr4 proto static
104.41.169.34 via 169.254.254.1 dev vnet0g85jrhr4 proto static
169.254.129.0/24 dev eth0 proto kernel scope link src 169.254.129.2
169.254.254.0/24 dev vnet0g85jrhr4 proto kernel scope link src 169.254.254.2
172.16.0.0/12 via 169.254.254.1 dev vnet0g85jrhr4 proto static
191.237.240.43 via 169.254.254.1 dev vnet0g85jrhr4 proto static
191.237.240.44 via 169.254.254.1 dev vnet0g85jrhr4 proto static
191.237.240.46 via 169.254.254.1 dev vnet0g85jrhr4 proto static
192.168.0.0/16 via 169.254.254.1 dev vnet0g85jrhr4 proto static
```

ガツンと増えました。デフォルトルートはeth0側ですが、統合したVNet(10.0.0.0/16)と、RFC 1918プライベートアドレス(10.0.0.0/8、172.16.0.0/12、192.168.0.0/16)向けのルートが、VNet向けのインターフェースから出ていくように設定されています。

また、他にも多くのアドレスレンジが追加されていますね。これは、サービスエンドポイントへ登録したサービスが使っているアドレスレンジです。

```
% az network list-service-tags -l japaneast -o json --query "values[].{id:id, addressPrefixes:properties.addressPrefixes}[?contains(id, 'Sql.JapanEast')]"
[
  {
    "addressPrefixes": [
      "13.78.61.196/32",
      "13.78.104.0/27",
      "13.78.104.32/29",
      "13.78.105.0/27",
      "13.78.121.203/32",
      "20.191.165.160/27",
      "20.191.165.192/27",
      "20.191.166.0/26",
      "23.102.69.95/32",
      "23.102.71.13/32",
      "23.102.74.190/32",
      "40.79.184.0/27",
      "40.79.184.32/29",
      "40.79.185.0/27",
      "40.79.192.0/27",
      "40.79.192.32/29",
      "40.79.193.0/27",
      "52.185.152.149/32",
      "52.243.32.19/32",
      "52.243.43.186/32",
      "104.41.168.103/32",
      "104.41.169.34/32",
      "191.237.240.43/32",
      "191.237.240.44/32",
      "191.237.240.46/32",
      "2603:1040:407::320/123",
      "2603:1040:407::380/121",
      "2603:1040:407:400::/123",
      "2603:1040:407:401::/123",
      "2603:1040:407:800::/123",
      "2603:1040:407:801::/123",
      "2603:1040:407:c00::/123",
      "2603:1040:407:c01::/123"
    ],
    "id": "Sql.JapanEast"
  }
]
```

VNetが配置されているのと同じリージョン(東日本)のAzure SQL DatabaseのサービスIPv4タグと一致します。

## VNet統合あり(WEBSITE_VNET_ROUTE_ALL = 1)

では最後に、WEBSITE_VNET_ROUTE_ALL = 1をアプリケーション設定に追加し、コンテナーを再起動します。これまで同様、コンテナーの中でネットワーク設定を確認します。

```
root@63b571dc31c3:~/site/wwwroot# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
3: vnet00e5jrhr4@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 5a:d6:31:fa:ab:91 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 169.254.254.5/24 brd 169.254.254.255 scope global vnet00e5jrhr4
       valid_lft forever preferred_lft forever
5: eth0@if56: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 0a:c0:56:65:b6:ad brd ff:ff:ff:ff:ff:ff link-netnsid 1
    inet 169.254.129.5/24 brd 169.254.129.255 scope global eth0
       valid_lft forever preferred_lft forever
```

再作成されていますが、WEBSITE_VNET_ROUTE_ALL = 1を設定する前と、インターフェースの数と役割は変わりません。では、ルートはどうでしょう。

```
root@63b571dc31c3:~/site/wwwroot# ip r
default via 169.254.254.1 dev vnet00e5jrhr4
169.254.129.0/24 dev eth0 proto static mtu 1500
169.254.254.0/24 dev vnet00e5jrhr4 proto kernel scope link src 169.254.254.5
```

ルートは大きく変わり、デフォルトルートがVNet側インターフェースに向きます。WEBSITE_VNET_ROUTE_ALL = 1を設定する前は、VNetやサービスエンドポイントのアドレスレンジが個別に登録されましたが、設定後はそれらのネットワークがデフォルト側にあるため、ルート数がすっきりします。
