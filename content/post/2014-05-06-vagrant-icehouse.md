---
date: "2014-05-06T00:00:00+09:00"
slug: "vagrant-icehouse"
title: いま最も楽にIcehouse環境を作る方法
category: Tips
tags: [Vagrant, OpenStack, Icehouse]
---
### あえて言おう、これは甘えであると
現時点でもっとも楽にIcehouse環境を構築できる方法だと思う。所要時間、約30分。

では始めましょう。[OpenStack Cloud Computing Cookbook](http://openstackr.wordpress.com/2014/05/01/openstack-cloud-computing-cookbook-the-icehouse-scripts/)の著者が提供しているツールを使います。使うのはVagrant、VirtualBox、Git。

### ほんと、これだけ
1.  Vagrant、VirtualBox、Gitが入ってること、バージョンと大まかな手順を[このページ](http://openstackr.wordpress.com/2014/05/01/openstack-cloud-computing-cookbook-the-icehouse-scripts/)で確認
2.  $ vagrant plugin install vagrant-cachier
3.  $ git clone https://github.com/OpenStackCookbook/OpenStackCookbook.git
4.  $ cd OpenStackCookbook
5.  $ git checkout icehouse
6.  $ vagrant up
7.  何度か管理者パスワードを入力
8.  $ vagrant ssh controller
9.  $ . /vagrant/openrc
10. $/vagrant/demo.sh

以上。Horizonコンソールは http://172.16.0.200/ から。 

### この環境だと30分でできた
- Vagrant 1.5.4
- VirtualBox 4.3.10
- Macbook Pro 2.3GHz クアッドコアIntel Core i7/メモリ16GB/SSD512GB


デモや新機能の試用くらいであればこれで十分ですね。  
著者に感謝。わたしは買いました。 -- [OpenStack Cloud Computing Cookbook Second Edition(Amazon.co.jp)](http://www.amazon.co.jp/OpenStack-Computing-Cookbook-Second-Edition-ebook/dp/B00FZMREUM/)