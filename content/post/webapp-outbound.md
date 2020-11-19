+++
Categories = ["Azure"]
Tags = ["Azure","Webapp"]
date = "2020-09-01T14:30:00+09:00"
title = "マルチテナント型 Azure Web AppsでアウトバウンドIPを固定する"

+++

## (2020/11/19更新)
この記事ではアウトバウンド通信をAzure Firewallに向けていますが、[NAT Gatewayにも向けられるようになりました](https://azure.github.io/AppService/2020/11/15/web-app-nat-gateway.html)

## 何の話か

ここ数週で同じ相談を3件いただきました。うごめくニーズを感じ取ったので、解決策を残しておきます。

実現したいことは *「専用型でVNetに注入できるASEではなく、マルチテナント型のWeb AppsでアウトバウンドのIPアドレスを固定したい」* です。気持ちは分かります。マルチテナント型のほうが、よりクラウドらしいですものね。やりましょう。

*(注)2020年9月時点の解決策です。Azureのネットワークは急に進化することがあるので、他の選択肢が生まれてないかをご確認ください*

## 実現したいこと

* マルチテナント型Web Appsに複数、ランダムに割り当てられるアウトバウンド通信用IPを使うのではなく、固定IPを割り当てたい
  * 「連携する外部サービス/システムがIPアドレスでフィルタリングしている」というケースが多い
* ついでにインターネットに出ていくトラフィックのログを採っておきたい
* できればWeb AppsからAzureの他サービスにはプライベートネットワークで接続したい
  * DBとか

## 解決策

* Web AppsのリージョンVNet統合機能を使い、アウトバウンドトラフィックをVNet上の統合用サブネットに転送します
  * WEBSITE_VNET_ROUTE_ALL を設定し、すべてのアウトバウンドトラフィックをVNetに向けます
* 統合用サブネットのデフォルトルートをAzure Firewallに向けます
  * Azure Firewallに割り当てたパブリックIPでインターネットに出ていきます
* Azureの他サービスにはプライベートエンドポイント経由でアクセスさせます
  * 名前解決でプライベートエンドポイントのIPが返ってくるよう、プライベートDNSゾーンを作ってリンクします

Linux Web AppにPython(Django)アプリを載せ、Azure Database for PostgreSQLに繋ぐ[サンプル](https://docs.microsoft.com/ja-jp/azure/app-service/tutorial-python-postgresql-app?tabs=bash%2Cclone)を例にすると、こんな感じです。

![Overview](https://raw.githubusercontent.com/ToruMakabe/Images/master/wa-ob-fw.jpg?raw=true "Overview")

コードを見たほうがピンとくると思うので、Terraformの構成ファイルをGistに置いておきます。上記の環境が一発で作れます。

[Azure Web Appsからのアウトバウンド通信をAzure FirewallのパブリックIPに固定する](https://gist.github.com/ToruMakabe/e5a41dd51bc998a975a91aba148f55d9)

では設定できているか、確認してみましょう。

まずはAzure Firewallに割り当てたIPでインターネットに出ているかです。該当のパブリックIPアドレスを確認します。

```
az network public-ip show -g rg-webapp-ob-fw -n pip-firewall
Name          ResourceGroup    Location    Zones    Address      AddressVersion    AllocationMethod    IdleTimeoutInMinutes    ProvisioningState
------------  ---------------  ----------  -------  -----------  ----------------  ------------------  ----------------------  -------------------
pip-firewall  rg-webapp-ob-fw  japaneast            20.48.76.82  IPv4              Static              4                       Succeeded
```

20.48.76.82 がAzure Firewallに割り当てたパブリックIPです。

ではWeb AppsにSSHし、そこから、送信元IPアドレスを返すWebサイト [ifconfig.io](http://ifconfig.io/) にcurlしてみます。

```
root@b48941bac7f4:/home# curl ifconfig.io
20.48.76.82
```

Azure Firewallに割り当てたパブリックIPでアクセスしていることが分かります。

合わせて、PostgreSQLへの接続がプライベートになっているか、名前解決を確認します。

```
root@b48941bac7f4:/home# dig psql-server-tomakabe.postgres.database.azure.com

; <<>> DiG 9.10.3-P4-Debian <<>> psql-server-tomakabe.postgres.database.azure.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 65111
;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1224
; OPT=65436: cc fa b8 63 02 7d eb 3a 85 5a 6e 20 80 21 e1 aa ("...c.}.:.Zn .!..")
;; QUESTION SECTION:
;psql-server-tomakabe.postgres.database.azure.com. IN A

;; ANSWER SECTION:
psql-server-tomakabe.postgres.database.azure.com. 300 IN CNAME psql-server-tomakabe.privatelink.postgres.data
base.azure.com.
psql-server-tomakabe.privatelink.postgres.database.azure.com. 10 IN A 10.0.3.4

;; Query time: 79 msec
;; SERVER: 127.0.0.11#53(127.0.0.11)
;; WHEN: Tue Sep 01 02:29:01 UTC 2020
;; MSG SIZE  rcvd: 160

```

エンドポイント用サブネットでPostgreSQL向けに割り当てられたプライベートIP 10.0.3.4 が返りました。

## オーバーキルみを感じるあなたへ

「アウトバウンドIPを固定したいけど、Azure Firewallのロギングやフィルタリングは要らないなー、NAT Gatewayくらいがちょうといいのに」という気持ち、わかります。

ぜひ清き一票を。

[(Azure Feedback) VNet NAT Gateway on App Service delegated subnet](https://feedback.azure.com/forums/169385-web-apps/suggestions/40129801-vnet-nat-gateway-on-app-service-delegated-subnet)
