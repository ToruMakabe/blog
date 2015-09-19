---
date: "2015-04-04T00:00:00+09:00"
slug: "terraform-openstack-minimum"
title: いきなり Terraform OpenStack Provider
category: Tips
tags: [Terraform, OpenStack]
---
### Terraform 0.4でOpenStack Providerリリース
以前からOpenStack対応は表明されていたのですが、いよいよ[v0.4](https://hashicorp.com/blog/terraform-0-4.html)でリリースされました。

### 小さくはじめましょう
この手のツールを試すときは、はじめから欲張ると苦労します。最小限の設定でひとまず動かすとクイックに幸せが訪れます。目標は10分。

### テストした環境
* Terraform 0.4
* Mac OS 10.10.2
* HP Helion Public Cloud

### OpenStackerのみだしなみ、環境変数
下記、環境変数はセットされてますよね。要確認。  

* OS_AUTH_URL  
* OS_USERNAME  
* OS_PASSWORD  
* OS_REGION_NAME  
* OS_TENANT_NAME  

### 最小限の構成ファイル
{{< gist 977209064bcfda66d085 >}}

これだけ。Providerの設定は書かなくていいです。Terraformは環境変数を見に行きます。Resource部は、最小限ということで、まずはインスタンスを起動し、Floating IPをつけるとこまで持っていきましょう。

### さあ実行
まずはterraform planコマンドで、実行計画を確認します。

    $ terraform plan
    Refreshing Terraform state prior to plan...


    The Terraform execution plan has been generated and is shown below.
    Resources are shown in alphabetical order for quick scanning. Green resources
    will be created (or destroyed and then created if an existing resource exists), yellow resources are being changed in-place, and red resources will be destroyed.

    Note: You didn't specify an "-out" parameter to save this plan, so when "apply" is called, Terraform can't guarantee this is what will execute.

    + openstack_compute_instance_v2.sample-server
        access_ip_v4:      "" => "<computed>"
        access_ip_v6:      "" => "<computed>"
        flavor_id:         "" => "my_flavor_id"
        flavor_name:       "" => "<computed>"
        floating_ip:       "" => "aaa.bbb.ccc.ddd"
        image_id:          "" => "my_image_id"
        image_name:        "" => "<computed>"
        key_pair:          "" => "my_keypair"
        name:              "" => "tf-sample"
        network.#:         "" => "<computed>"
        region:            "" => "my_region"
        security_groups.#: "" => "1"
        security_groups.0: "" => "my_sg"

定義通りに動きそうですね。では実行。applyです。

    $ terraform apply  
    openstack_compute_instance_v2.sample-server: Creating...  
        access_ip_v4:      "" => "<computed>"  
        access_ip_v6:      "" => "<computed>"  
        flavor_id:         "" => "my_flavor"  
        flavor_name:       "" => "<computed>"  
        floating_ip:       "" => "aaa.bbb.ccc.ddd"  
        image_id:          "" => "my_image_id"  
        image_name:        "" => "<computed>"  
        key_pair:          "" => "my_keypair"  
        name:              "" => "tf-sample"  
        network.#:         "" => "<computed>"  
        region:            "" => "my_region"
        security_groups.#: "" => "1"
        security_groups.0: "" => "my_sg"
    openstack_compute_instance_v2.test-server: Creation complete

    Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

    The state of your infrastructure has been saved to the path below. This state is required to modify and destroy your infrastructure, so keep it safe. To inspect the complete state use the `terraform show` command.


とても楽ちんですね。あとはオプションを追加して込み入った構成に挑戦してみてください。
