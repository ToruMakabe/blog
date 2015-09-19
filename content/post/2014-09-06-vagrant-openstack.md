---
date: "2014-09-06T00:00:00+09:00"
slug: "vagrant-openstack"
title: Vagrant-hpからVagrant-openstack-pluginへ
category: Tips
tags: [Vagrant, OpenStack, HP Public Cloud]
---
### ツールやSDKはボチボチ集約したほうが
これまでHP Public Cloudむけの[Vagrant](http://www.vagrantup.com/)は、[vagrant-hp plug-in](https://github.com/mohitsethi/vagrant-hp)を[使って](http://torumakabe.github.io/tips/2014/05/05/vagrant-hpcloud/)ました。でも最近、より汎用的で開発が活発な[vagrant-openstack-plugin](https://github.com/cloudbau/vagrant-openstack-plugin)へ鞍替えを画策しております。そろそろOpenStackのツールやSDKは、スタンダードになりそうなものを盛り上げた方がいいかな、と思っていたところだったので。

多様性はオープンソースの魅力ですが、選択肢が多すぎるとユーザーは迷子になります。OpenStackのアプリデベロッパーは増えつつあるので、そろそろコミュニティでツールやSDKの集約を考える時期かなあ、と。

さて、このPlug-in、あまり情報ないので、使用感をまとめておきます。

### 前提条件
- Vagrant 1.6.3
- vagrant-openstack-plugin 0.8.0
- HP Public Cloud (2014/9/6)

### プラグインのインストールと前準備
[Github](https://github.com/cloudbau/vagrant-openstack-plugin)を見て、プラグインのインストールとboxファイルの作成を行ってください。boxファイルがない状態でvagrant upすると怒られます。

### ではVagrantfileを見てみましょう
{{< gist c9de20c61752864aca86 >}}

これがわたしが作ったVagrantfileです。見ての通りですが、以下に補足します。

- フレーバーとイメージ名は正規表現で指定できます。
- OpenStack CLI群と同じ環境変数を使ってます。
- Floating IPは":auto"指定にてVMへ自動割当できますが、IPは事前に確保しておいてください。

で、ふつーに動きます。乗り換え決定です。

### スナップショット便利
vagrant-hpでは使えなかったはず。こいつは便利だ。

    $ vagrant openstack snapshot -n lab01_snap
    ==> default: This server instance is snapshoting!
    ==> default: Snapshot is ok