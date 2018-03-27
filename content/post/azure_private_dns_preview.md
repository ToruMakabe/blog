+++
Categories = ["Azure"]
Tags = ["Azure", "DNS"]
date = "2018-03-27T00:10:30+09:00"
title = "Azure DNS Private Zonesの動きを確認する"

+++

## プライベートゾーンのパブリックプレビュー開始
Azure DNSのプライベートゾーン対応が、全リージョンでパブリックプレビューとなりました。ゾーンとプレビューのプライベートとパブリックが入り混じって、なにやら紛らわしいですが。

さて、このプライベートゾーン対応ですが、名前のとおりAzure DNSをプライベートな仮想ネットワーク(VNET)で使えるようになります。加えて、しみじみと嬉しい便利機能がついています。

* Split-Horizonに対応します。VNET内からの問い合わせにはプライベートゾーン、それ以外からはパブリックゾーンのレコードを返します。
* 仮想マシンの作成時、プライベートゾーンへ自動でホスト名を追加します。
* プライベートゾーンとVNETをリンクして利用します。複数のVNETをリンクすることが可能です。
* リンクの種類として、仮想マシンホスト名の自動登録が行われるVNETをRegistration VNET、名前解決(正引き)のみ可能なResolution VNETがあります。
* プライベートゾーンあたり、Registration VNETの現時点の上限数は1、Resolution VNETは10です。

公式ドキュメントは[こちら](https://docs.microsoft.com/en-us/azure/dns/private-dns-overview)。現時点の[制約もまとまっている](https://docs.microsoft.com/en-us/azure/dns/private-dns-overview#limitations)ので、目を通しておきましょう。

## 動きを見てみよう
公式ドキュメントには[想定シナリオ](https://docs.microsoft.com/en-us/azure/dns/private-dns-scenarios)があり、これを読めばできることがだいたい分かります。ですが、名前解決は呼吸のようなもの、体に叩き込みたいお気持ちです。手を動かして確認します。

### 事前に準備する環境
下記リソースを先に作っておきます。手順は割愛。ドメイン名はexample.comとしましたが、適宜読み替えてください。

* VNET *2
  * vnet01
    * subnet01
      * subnet01-nsg (allow ssh)
  * vnet02
    * subnet01
      * subnet01-nsg (allow ssh)
* Azure DNS Public Zone
  * example.com

### Azure CLIへDNS拡張を導入
プレビュー機能をCLIに導入します。いずれ要らなくなるかもしれませんので、要否は[公式ドキュメント](https://docs.microsoft.com/en-us/azure/dns/private-dns-getstarted-cli#to-installuse-azure-dns-private-zones-feature-public-preview)で確認してください。

```
$ az extension add --name dns
```

### プライベートゾーンの作成
既存のゾーンを確認します。パブリックゾーンがあります。

```
$ az network dns zone list -o table
ZoneName      ResourceGroup             RecordSets    MaxRecordSets
------------  ----------------------  ------------  ---------------
example.com   common-global-rg                   2             5000
```

プライベートゾーンを作成します。Registration VNETとしてvnet01をリンクします。[現時点の制約](https://docs.microsoft.com/en-us/azure/dns/private-dns-overview#limitations)で、リンク時にはVNET上にVMが無い状態にする必要があります。

```
$ az network dns zone create -g private-dns-poc-ejp-rg -n example.com --zone-type Private --registration-vnets vnet01
```

同じ名前のゾーンが2つになりました。

```
$ az network dns zone list -o table
ZoneName      ResourceGroup             RecordSets    MaxRecordSets
------------  ----------------------  ------------  ---------------
example.com   common-global-rg                   2             5000
example.com   private-dns-poc-ejp-rg             1             5000
```

### Registration VNETへVMを作成
VMを2つ作ります。1つにはインターネット経由でsshするので、パブリックIPを割り当てます。

```
$ BASE_NAME="private-dns-poc-ejp"
$ az network public-ip create -n vm01-pip -g ${BASE_NAME}-rg
$ az network nic create -g ${BASE_NAME}-rg -n vm01-nic --public-ip-address vm01-pip --vnet vnet01 --subnet subnet01
$ az vm create -g ${BASE_NAME}-rg -n vm01 --image Canonical:UbuntuServer:16.04.0-LTS:latest --size Standard_B1s --nics vm01-nic
$ az network nic create -g ${BASE_NAME}-rg -n vm02-nic --vnet vnet01 --subnet subnet01
$ az vm create -g ${BASE_NAME}-rg -n vm02 --image Canonical:UbuntuServer:16.04.0-LTS:latest --size Standard_B1s --nics vm02-nic
```

### パブリックIPをパブリックゾーンへ登録
Split-Horizonの動きを確認したいので、パブリックIPをパブリックゾーンへ登録します。

```
$ az network public-ip show -g private-dns-poc-ejp-rg -n vm01-pip --query ipAddress
"13.78.84.84"
$ az network dns record-set a add-record -g common-global-rg -z example.com -n vm01 -a 13.78.84.84
```

パブリックゾーンで名前解決できることを確認します。

```
$ nslookup vm01.example.com
Server:         103.5.140.1
Address:        103.5.140.1#53

Non-authoritative answer:
Name:   vm01.example.com
Address: 13.78.84.84
```

### Registration VNETの動きを確認
vnet01のvm01へ、パブリックIP経由でsshします。

```
$ ssh vm01.example.com
```

同じRegistration VNET上のvm02を正引きします。ドメイン名無し、ホスト名だけでnslookupすると、VNETの内部ドメイン名がSuffixになります。

```
vm01:~$ nslookup vm02
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   vm02.aioh0amlfdze5drhlpb1ktqwxd.lx.internal.cloudapp.net
Address: 10.0.0.5
```

ドメイン名をつけてみましょう。Nameはvnet01にリンクしたプライベートゾーンのドメイン名になりました。
```
vm01:~$ nslookup vm02.example.com
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   vm02.example.com
Address: 10.0.0.5
```

逆引きもできます。

```
vm01:~$ nslookup 10.0.0.5
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
5.0.0.10.in-addr.arpa   name = vm02.example.com.

Authoritative answers can be found from:
```

### Split-Horizonの動きを確認
さて、いま作業をしているvm01には、インターネット経由でパブリックゾーンで名前解決してsshしたわけですが、プライベートなVNET内でnslookupするとどうなるでしょう。

```
vm01:~$ nslookup vm01.example.com
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   vm01.example.com
Address: 10.0.0.4
```

プライベートゾーンで解決されました。Split-Horizonが機能していることが分かります。

あ、どうでもいいことですが、Split-Horizonって戦隊モノの必殺技みたいなネーミングですね。叫びながら地面に拳を叩きつけたい感じ。

### Resolution VNETの動きを確認
vnet02を作成し、Resolution VNETとしてプライベートゾーンとリンクします。そして、vnet02にvm03を作ります。vm03へのsshまで一気に進めます。

```
$ BASE_NAME="private-dns-poc-ejp"
$ az network vnet create -g ${BASE_NAME}-rg -n vnet02 --address-prefix 10.1.0.0/16 --subnet-name subnet01
$ az network vnet subnet update -g ${BASE_NAME}-rg -n subnet01 --vnet-name vnet02 --network-security-group subnet01-nsg
$ az network public-ip create -n vm03-pip -g ${BASE_NAME}-rg
$ az network dns zone update -g private-dns-poc-ejp-rg -n example.com --resolution-vnets vnet02
$ az network nic create -g ${BASE_NAME}-rg -n vm03-nic --public-ip-address vm03-pip --vnet vnet02 --subnet subnet01
$ az vm create -g ${BASE_NAME}-rg -n vm03 --image Canonical:UbuntuServer:16.04.0-LTS:latest --size Standard_B1s --nics vm03-nic
$ az network public-ip show -g private-dns-poc-ejp-rg -n vm03-pip --query ipAddress
"13.78.54.133"
$ ssh 13.78.54.133
```

名前解決の確認が目的なので、vnet01/02間はPeeringしません。

では、vnet01上のvm01を正引きします。ドメイン名を指定しないと、解決できません。vnet02上にvm01がある、と指定されたと判断するからです。

```
vm03:~$ nslookup vm01
Server:         168.63.129.16
Address:        168.63.129.16#53

** server can't find vm01: SERVFAIL
```

ではプライベートゾーンのドメイン名をつけてみます。解決できました。

```
vm03:~$ nslookup vm01.example.com
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   vm01.example.com
Address: 10.0.0.4
```

Resolution VNETからは、逆引きできません。

```
vm03:~$ nslookup 10.0.0.4
Server:         168.63.129.16
Address:        168.63.129.16#53

** server can't find 4.0.0.10.in-addr.arpa: NXDOMAIN
```

ところでRegistration VNETからResolution VNETのホスト名をnslookupするとどうなるでしょう。

```
$ ssh vm01.example.com
vm01:~$ nslookup vm03
Server:         168.63.129.16
Address:        168.63.129.16#53

** server can't find vm03: SERVFAIL

vm01:~$ nslookup vm03.example.com
Server:         168.63.129.16
Address:        168.63.129.16#53

** server can't find vm03.example.com: NXDOMAIN
```

ドメイン名あり、なしに関わらず、名前解決できません。VNETが別なのでVNETの内部DNSで解決できない、また、Resolution VNETのVMはレコードがプライベートゾーンに自動登録されないことが分かります。