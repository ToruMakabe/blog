+++
Categories = ["Azure"]
Tags = ["Azure", "Packer", "ARM"]
date = "2016-03-17T23:00:00+09:00"
title = "PackerとAnsibleでAzureのGolden Imageを作る(ARM対応)"

+++

## いつの間に
ナイスな感じにイメージを作ってくれるPackerですが、いつの間にか[Azure ARM対応のBuilder](https://www.packer.io/docs/builders/azure.html)が出ておりました。0.10からかな。早く言ってください。

## ansible_localと組み合わせたサンプル
さっそく試してそつなく動くことを確認しました。サンプルを[Githubにあげておきます](https://github.com/ToruMakabe/Packer_Azure_Sample)。

手の込んだ設定もできるように、Provisonerにansible_localを使うサンプルで。

### 前準備
* リソースグループとストレージアカウントを作っておいてください。そこにイメージが格納されます。
* 認証情報の類は外だしします。builder/variables.sample.jsonを参考にしてください。
* Packerの構成ファイルはOSに合わせて書きます。サンプルのbuilder/ubuntu.jsonはubuntuの例です。
    * Azure ARM BuilderはまだWindowsに対応していません。開発中とのこと。
* ansibleはapache2をインストール、サービスEnableするサンプルにしました。

### サンプル
ubuntu.jsonはこんな感じです。

    {
      "variables": {
        "client_id": "",
        "client_secret": "",
        "resource_group": "",
        "storage_account": "",
        "subscription_id": "",
        "tenant_id": ""
      },
      "builders": [{
        "type": "azure-arm",
    
        "client_id": "{{user `client_id`}}",
        "client_secret": "{{user `client_secret`}}",
        "resource_group_name": "{{user `resource_group`}}",
        "storage_account": "{{user `storage_account`}}",
        "subscription_id": "{{user `subscription_id`}}",
        "tenant_id": "{{user `tenant_id`}}",
    
        "capture_container_name": "images",
        "capture_name_prefix": "packer",
    
        "image_publisher": "Canonical",
        "image_offer": "UbuntuServer",
        "image_sku": "14.04.3-LTS",
    
        "location": "Japan West",
        "vm_size": "Standard_D1"
      }],
      "provisioners": [{
        "type": "shell",
          "scripts": [
            "../script/ubuntu/provision.sh"
        ]
      },
      {
        "type": "ansible-local",
        "playbook_file": "../ansible/baseimage.yml",
        "inventory_file": "../ansible/hosts",
        "role_paths": [
          "../ansible/roles/baseimage"
        ]
      },
      {
        "type": "shell",
          "scripts": [
            "../script/ubuntu/deprovision.sh"
        ]
      }]
    }
    
waagentによるde-provisionはansibleでもできるのですが、他OS対応も考えて、最後に追いshellしてます。他ファイルは[Github](https://github.com/ToruMakabe/Packer_Azure_Sample)でご確認を。

これで手順書&目視&指差し確認でイメージ作るのを、やめられそうですね。