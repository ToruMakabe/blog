---
date: "2014-01-05T00:00:00+09:00"
slug: "hpcos-vbox-scripts"
title: HP Cloud OS Sandbox向け VirtualBox 環境構築スクリプト
category: Tips
tags: [HP Cloud OS, OpenStack, VirtualBox]
---
### HP Cloud OS Sandboxが公開された
先日、HP Cloud OS Sandboxが[公開](https://cloudos.hpwsportal.com/#/Product/{"productId":"570"}/Show)されました。HP Cloud OSとは、OpenStackをコアに、HPが便利機能を追加したソフトウェアスタックです。その試用版がSandboxです。

OpenStackは日々成長していますが、地味な運用まわりの機能に物足りなさがあります。そこでHPは早い時期からOpenStackの商用製品・サービス化に取り組んできた経験から、HP Cloud OSではOpenStackの周辺に便利機能を付加しています。GUIでさくっとノード追加できるとか、複数のOpenStackクラウドを束ねて管理するとか。素のOpenStackもいいですが、味付けしたものもまたよし、ですよ。

### 気軽に試したい人向けに
導入ドキュメントは[公開](http://docs.hpcloud.com/cloudos)されていますので、ここで必要な[環境](http://docs.hpcloud.com/cloudos/prepare/supportmatrix/)を確認できます。が、ちょっとリッチですね。本気で使うのであれば、このくらいあったほうがいいでしょうけど。そこで、お気軽に試したいという人へ、VirtualBox環境への導入手順をご紹介します。

### VirtualBoxにHP Cloud OS Sandboxを導入するステップ
導入手順をざっくりまとめます。
1. VirtualBoxのホストオンリーネットワークを作成する
2. HP Cloud OS adminノードのVMを作成し、ISOイメージからインストールする
3. HP Cloud OS adminノードの種々パラメータを設定し、ビルドする
4. OpenStack controller、computeノード用のVMを作成しパワーオン。PXEでインストールする
5. 作成したVMをHP Cloud OS環境に取り込む
6. HP Cloud OS環境下に取り込んだVMをOpenStack controller、computeノードとして割り当て、もろもろの機能をインストールする

### GUIでチマチマとVirtualBox環境作りたくないよね
VirtualBoxは便利なんですけど、GUIで複数ノードのパラメータを設定するの、めんどうです。で、かなりの確率でミスります。ここはひとつ、できるところはスクリプトでやっちゃいましょう。前述した手順の1、2、4は、できるので。

### 実績あり環境
- Macbook Pro 2.3GHz クアッドコアIntel Core i7/メモリ16GB/SSD512GB
- 各VMへのメモリ割り当ては、admin(4GB)、controller(4GB)、compute(2GB)
- メモリ量はスクリプト内で指定していますので、適宜調整して下さい
- 搭載メモリ8GBマシンだと厳しいです。admin向けはケチらない方がいいです
- Mac OS X 10.9.1
- VirtualBox 4.3.6

なおシェルスクリプトで書いてますが、中身はVirtualBoxのVBoxManageコマンドの羅列なので、いじれば他環境にも流用できるかと。

### VirtualBoxのホストオンリーネットワークを作成する
{{< gist 8255299 >}}
hostonlyif create時に名前指定ができないのでvboxnet0、vboxnet1決め打ちにしましたが、環境にあわせて下さい。

### HP Cloud OS adminノードのVMを作成し、ISOイメージからインストールする
{{< gist 8255339 >}}
modifyvm --hostonlyadapter(2つ)、createhd、storageattach(2つ)のパラメータは環境にあわせて下さい。

### OpenStack controllerノード用のVMを作成しパワーオン。PXEでインストールする
{{< gist 8255354 >}}
modifyvm --hostonlyadapter(2つ)、createhd、storageattachのパスは環境にあわせて下さい。

### OpenStack computeノード用のVMを作成しパワーオン。PXEでインストールする
{{< gist 8255361 >}}
modifyvm --hostonlyadapter(2つ)、createhd、storageattachのパスは環境にあわせて下さい。

それではお楽しみ下さい。