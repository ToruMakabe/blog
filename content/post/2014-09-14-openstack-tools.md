---
date: "2014-09-14T00:00:00+09:00"
slug: "openstack-tools"
title: OpenStackのツール環境をImmutableに整える
category: Tips
tags: [Vagrant, OpenStack, Ansible]
---
### タイトルは釣りです
すいません。でも、日本のどこかに、わたしを待ってる、理解し合える人がいらっしゃると思います。

### なぜ必要か?
いけてるOpenStackerは、相手にするOpenStack環境がオンプレであろうがパブリッククラウドであろうが、すぐにコマンド叩いて「なるほどこの環境は。。。ニヤリ」とできるものです。そういうものです。

### やりたいこと
- OpenStack CLIなどのツールを詰め込んだ環境を、必要な時に、すぐ使いたい・作りたい
- Windows、Macどちらでも同様の環境にしたい
- 相手にするOpenStackがオンプレでも、パブリッククラウドでも、また、ツールがぶら下がっているネットワーク環境の違いも、設定やスクリプトで吸収
- Windows、Mac環境を汚さない、また、汚されない
- コマンド2、3発程度で、気軽に作って消せる
- VMできたらすぐログイン、即OpenStack CLIが使える

### 方針
- OpenStackの各種ツールを動かすOSはLinuxとし、VM上に作る
- VagrantでWindows/Macの違いを吸収する
- VMイメージをこねくり回さず、常にまっさらなベースOSに対し構成管理ツールでプロビジョニングを行う
- 構成管理ツールはAnsibleを使う(本を買ったので、使いたかっただけ)

### 前提条件
- Windows 8.1 & VMware Worksation 10.0.3
- OSX 10.9.4 & VirtualBox 4.3.16
- Vagrant 1.6.5  (VMware用ライセンス買いました)
- ひとまずOpenStack CLIを使えるところまで作る

### ではVagrantfileを見てみましょう
{{< gist a470e86a1477cd76d4f4 >}}

これがわたしが作ったVagrantfileです。見ての通りですが、以下に補足します。

- VMwareとVirtualBoxでなるべく環境を合わせるため、opscodeの[Bento](https://github.com/opscode/bento)で、事前にboxファイルを作ってます。ubuntu14.04としました。
- 実行ディレクトリにprovision.shを置きます。
- provision.shでubuntuへansibleをインストールし、追って入れたてホヤホヤのansibleで環境を整えます。
- 実行ディレクトリ内のansibleディレクトリに、ansibleのplaybook(site.yml)と変数定義ファイル(vars/env.yml)を置きます。
- hostsファイルには以下のようにlocalhostを定義します。

    [localhost]  
    127.0.0.1 ansible_connection=local  

#### provision.sh解説
{{< gist 57ae9f8edbe6cf30cd16 >}}

ansibleのインストールとplaybookの実行。playbookの実行が回りくどい感じなのは、Vagrantのフォルダ同期機能でパーミッションが正しく設定できなかったゆえのワークアラウンドです。

#### playbook(site.yml)解説
{{< gist 6c5d8ae296948b8d4070 >}}

- varsディレクトリ配下に、環境変数を定義したenv.ymlを置きます。ここで対象のOpenStack環境を指定します。

    OS_TENANT_NAME: your_tenant_name  
    OS_USERNAME: your_username  
    ....  

  という感じで並べてください。.bashrcに追加されます。
- タイムゾーンをAsia/Tokyoにします。
- 必要なパッケージ、pipの導入後、OpenStack CLI群をインストールします。

### Windowsでの実行例
Vagrant & AnsibleはMacの情報が多いので、ここではWindowsでの実行例を。PowerShellを管理者権限で起動し、Vagrantfileやprovision.sh、ansible関連ファイルが住むディレクトリでvagrant up。

    PS C:\Users\hoge> vagrant up
    Bringing machine 'default' up with 'vmware_workstation' provider...
    ==> default: Cloning VMware VM: 'opscode-ubuntu1404'. This can take some time...
    (snip)
    ==> default: TASK: [install OpenStack CLIs] ************************************************
    ==> default: changed: [127.0.0.1] => (item=python-neutronclient)
    ==> default: changed: [127.0.0.1] => (item=python-novaclient)
    ==> default: changed: [127.0.0.1] => (item=python-cinderclient)
    ==> default: changed: [127.0.0.1] => (item=python-keystoneclient)
    ==> default: changed: [127.0.0.1] => (item=python-swiftclient)
    ==> default: changed: [127.0.0.1] => (item=python-keystoneclient)
    ==> default: changed: [127.0.0.1] => (item=python-glanceclient)
    ==> default: changed: [127.0.0.1] => (item=python-troveclient)
    ==> default: changed: [127.0.0.1] => (item=python-designateclient)
    ==> default:
    ==> default: PLAY RECAP ********************************************************************
    ==> default: 127.0.0.1                  : ok=8    changed=7    unreachable=0    failed=0

うまく動いたようです。

    PS C:\Users\hoge> vagrant ssh
    cygwin warning:
      MS-DOS style path detected: C:/Users/hoge/.vagrant.d/insecure_private_key
      Preferred POSIX equivalent is: /cygdrive/c/Users/hoge/.vagrant.d/insecure_private_key
      CYGWIN environment variable option "nodosfilewarning" turns off this warning.
      Consult the user's guide for more details about POSIX paths:
        http://cygwin.com/cygwin-ug-net/using.html#using-pathnames
    Welcome to Ubuntu 14.04 LTS (GNU/Linux 3.13.0-24-generic x86_64)

     * Documentation:  https://help.ubuntu.com/
    Last login: Sun Apr 20 02:21:46 2014 from 172.16.230.1

vagrant sshでサクッとログイン。ちなみに、これだけのためにcygwin入れてます。負けは認めます。

    vagrant@vagrant:~$ nova list
    +----+------+--------+------------+-------------+----------+
    | ID | Name | Status | Task State | Power State | Networks |
    +----+------+--------+------------+-------------+----------+
    +----+------+--------+------------+-------------+----------+

いきなりnovaコマンド使えます。

なおproxy環境下では、/etc/apt/apt.conf、.bashrcやplaybookにproxy設定をするよう、provision.shとplaybook(site.yml)をいじれば動くと思います。まだやってませんが。