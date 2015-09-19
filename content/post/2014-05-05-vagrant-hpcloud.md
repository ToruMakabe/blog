---
date: "2014-05-05T00:00:00+09:00"
slug: "vagrant-hpcloud"
title: Vagrant HP Public Cloud Pluginを試す
category: Tips
tags: [Vagrant, HP Public Cloud]
---
### みんな大好きHashiCorp
クラウド界隈のデベロッパーから熱く注目されているHashiCorp。[Packer](http://www.packer.io/)、[Serf](http://www.serfdom.io/)、[Consul](http://www.consul.io/)と立て続けにイカしてる製品をリリースしております。まあ小生は、正直なところConsulあたりから置いてかれてますが。でも、やはり代表作は[Vagrant](http://www.vagrantup.com/)でしょう。vagrant up! vagrant destroy! いやー気軽でいいですね。

VagrantはローカルのVirtualBoxやVMwareの他に、Providerとしてパブリッククラウドを選択できるのも魅力です。そこで当エントリではHP Public Cloud向けのVagrant Pluginを試してみます。

### 前提条件
- Vagrant 1.5.4
- vagrant-hp 0.1.4
- HP Public Cloud (2014/5/5)

### プラグインのインストールと前準備
[Github](https://github.com/mohitsethi/vagrant-hp)を見て、プラグインのインストールとboxファイルの作成を行ってください。boxファイルがない状態でvagrant upすると怒られます。

### ではVagrantfileを見てみましょう
{{< gist 25a33c679492676bb626 >}}

これがわたしが作ったVagrantfileです。見ての通りですが、以下に補足します。2014/5/5時点、[Github](https://github.com/mohitsethi/vagrant-hp)の説明には若干のトラップがありますのでご注意を。

- イメージにUbuntu 14.04 LTSを使う例です。
- Availability Zoneパラメータには、Regionを指定してください。おっぷ。ここでちょいハマった。
- Security Groupは任意ですが、sshしたい場合はsshを通すSecurity Groupを指定してください。
- Floating IPは任意ですが、外部ネットワークからsshしたいときは必須です。
- ネットワーク指定は任意ですが、複数ネットワークを有している場合は、いずれか指定してください。

### それではさっそくvagrant up
    $ vagrant up --provider=hp
    Bringing machine 'default' up with 'hp' provider...
    WARNING: Nokogiri was built against LibXML version 2.8.0, but has dynamically loaded 2.9.1
    ==> default: Warning! The HP provider doesn't support any of the Vagrant
    ==> default: high-level network configurations (`config.vm.network`). They
    ==> default: will be silently ignored.
    ==> default: Finding flavor for server...
    ==> default: Finding image for server...
    ==> default: Finding floating-ip...
    ==> default: Launching a server with the following settings...
    ==> default:  -- Flavor: standard.xsmall
    ==> default:  -- Image: Ubuntu Server 14.04 LTS (amd64 20140416.1) - Partner Image
    ==> default:  -- Name: hogehoge
    ==> default:  -- Key-name: your_keypair_name
    ==> default:  -- Security Groups: ["default", "http"]
    ==> default: Finding network...
    ==> default: Waiting for the server to be built...
    ==> default: Waiting for SSH to become available...
    ==> default: Machine is booted and ready for use!
    ==> default: Rsyncing folder: /your_path/data/ => /vagrant/data

できたっぽい。--provider=hpを忘れずに。

### 間髪入れずにvagrant ssh
    $ vagrant ssh
    WARNING: Nokogiri was built against LibXML version 2.8.0, but has dynamically loaded 2.9.1
    Welcome to Ubuntu 14.04 LTS (GNU/Linux 3.13.0-24-generic x86_64)

    * Documentation:  https://help.ubuntu.com/

    System information disabled due to load higher than 1.0

    Get cloud support with Ubuntu Advantage Cloud Guest:
        http://www.ubuntu.com/business/services/cloud

    0 packages can be updated.
    0 updates are security updates.


    ubuntu@hogehoge:~$ ls /vagrant/data
    test.txt

フォルダ同期も効いてますね。んー、楽ちん。

それではお楽しみ下さい。