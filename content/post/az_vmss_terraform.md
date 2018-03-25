+++
Categories = ["Azure"]
Tags = ["Azure", "AZ", "VMSS", "Terraform"]
date = "2018-03-26T00:08:30+09:00"
title = "AzureのAvailability Zonesへ分散するVMSSをTerraformで作る"

+++

## 動機
Terraform Azure Provider 1.3.0で、VMSSを作る際にAvailability Zonesを指定できるように[なりました](https://github.com/terraform-providers/terraform-provider-azurerm/pull/811)。Availability Zonesはインフラの根っこの仕組みなので、現在(2018/3)限定されたリージョンで長めのプレビュー期間がとられています。ですが、GAやグローバル展開を見据え、素振りしておきましょう。

## 前提条件
* Availability Zones対応リージョンを選びます。現在は[5リージョン](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#regions-that-support-availability-zones)です。この記事ではEast US 2とします。
* Availability Zonesのプレビューに[サインアップ](https://docs.microsoft.com/ja-jp/azure/availability-zones/az-overview)済みとします。
* bashでsshの公開鍵が~/.ssh/id_rsa.pubにあると想定します。
* 動作確認した環境は以下です。
  * Terraform 0.11.2
  * Terraform Azure Provider 1.3.0
  * WSL (ubuntu 16.04)
  * macos (High Sierra 10.13.3)

## コード
以下のファイルを同じディレクトリに作成します。

### Terraform メインコード
VMSSと周辺リソースを作ります。

* 最終行近くの "zones = [1, 2, 3]" がポイントです。これだけで、インスタンスを散らす先のゾーンを指定できます。
* クロスゾーン負荷分散、冗長化するため、Load BalancerとパブリックIPのSKUをStandardにします。

[main.tf]
```
resource "azurerm_resource_group" "poc" {
  name     = "${var.resource_group_name}"
  location = "East US 2"
}

resource "azurerm_virtual_network" "poc" {
  name                = "vnet01"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  location            = "${azurerm_resource_group.poc.location}"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "poc" {
  name                      = "subnet01"
  resource_group_name       = "${azurerm_resource_group.poc.name}"
  virtual_network_name      = "${azurerm_virtual_network.poc.name}"
  address_prefix            = "10.0.2.0/24"
  network_security_group_id = "${azurerm_network_security_group.poc.id}"
}

resource "azurerm_network_security_group" "poc" {
  name                = "nsg01"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  location            = "${azurerm_resource_group.poc.location}"

  security_rule = [
    {
      name                       = "allow_http"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                       = "allow_ssh"
      priority                   = 101
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
  ]
}

resource "azurerm_public_ip" "poc" {
  name                         = "pip01"
  resource_group_name          = "${azurerm_resource_group.poc.name}"
  location                     = "${azurerm_resource_group.poc.location}"
  public_ip_address_allocation = "static"
  domain_name_label            = "${var.scaleset_name}"

  sku = "Standard"
}

resource "azurerm_lb" "poc" {
  name                = "lb01"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  location            = "${azurerm_resource_group.poc.location}"

  frontend_ip_configuration {
    name                 = "fipConf01"
    public_ip_address_id = "${azurerm_public_ip.poc.id}"
  }

  sku = "Standard"
}

resource "azurerm_lb_backend_address_pool" "poc" {
  name                = "bePool01"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  loadbalancer_id     = "${azurerm_lb.poc.id}"
}

resource "azurerm_lb_rule" "poc" {
  name                           = "lbRule"
  resource_group_name            = "${azurerm_resource_group.poc.name}"
  loadbalancer_id                = "${azurerm_lb.poc.id}"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "fipConf01"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.poc.id}"
  probe_id                       = "${azurerm_lb_probe.poc.id}"
}

resource "azurerm_lb_probe" "poc" {
  name                = "http-probe"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  loadbalancer_id     = "${azurerm_lb.poc.id}"
  port                = 80
}

resource "azurerm_lb_nat_pool" "poc" {
  count                          = 3
  name                           = "ssh"
  resource_group_name            = "${azurerm_resource_group.poc.name}"
  loadbalancer_id                = "${azurerm_lb.poc.id}"
  protocol                       = "Tcp"
  frontend_port_start            = 50000
  frontend_port_end              = 50119
  backend_port                   = 22
  frontend_ip_configuration_name = "fipConf01"
}

data "template_cloudinit_config" "poc" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = "${file("${path.module}/cloud-config.yaml")}"
  }
}

resource "azurerm_virtual_machine_scale_set" "poc" {
  name                = "${var.scaleset_name}"
  resource_group_name = "${azurerm_resource_group.poc.name}"
  location            = "${azurerm_resource_group.poc.location}"
  upgrade_policy_mode = "Manual"

  sku {
    name     = "Standard_B1s"
    tier     = "Standard"
    capacity = 3
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name_prefix = "pocvmss"
    admin_username       = "${var.admin_username}"
    admin_password       = ""
    custom_data          = "${data.template_cloudinit_config.poc.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${file("~/.ssh/id_rsa.pub")}"
    }
  }

  network_profile {
    name    = "terraformnetworkprofile"
    primary = true

    ip_configuration {
      name                                   = "PoCIPConfiguration"
      subnet_id                              = "${azurerm_subnet.poc.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.poc.id}"]
      load_balancer_inbound_nat_rules_ids    = ["${element(azurerm_lb_nat_pool.poc.*.id, count.index)}"]
    }
  }

  zones = [1, 2, 3]
}
```

### cloud-init configファイル
各インスタンスがどのゾーンで動いているか確認したいので、インスタンス作成時にcloud-initでWebサーバーを仕込みます。メタデータからインスタンス名と実行ゾーンを引っ張り、nginxのドキュメントルートに書きます。

[cloud-config.yaml]
```
#cloud-config
package_upgrade: true
packages:
  - nginx
runcmd:
  - 'echo "[Instance Name]: `curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2017-12-01&format=text"`    [Zone]: `curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/zone?api-version=2017-12-01&format=text"`" > /var/www/html/index.nginx-debian.html'
```

インスタンス作成時、パッケージの導入やアップデートに時間をかけたくない場合は、Packerなどで前もってカスタムイメージを作っておくのも手です。

* [Packer を使用して Azure に Linux 仮想マシンのイメージを作成する方法](https://docs.microsoft.com/ja-jp/azure/virtual-machines/linux/build-image-with-packer)
* [Terraform を使用して Packer カスタム イメージから Azure 仮想マシン スケール セットを作成する](https://docs.microsoft.com/ja-jp/azure/terraform/terraform-create-vm-scaleset-network-disks-using-packer-hcl)

### Terraform 変数ファイル
変数は別ファイルへ。

[variables.tf]
```
variable "resource_group_name" {
  default = "your-rg"
}

variable "scaleset_name" {
  default = "yourvmss01"
}

variable "admin_username" {
  default = "yourname"
}
```

## 実行
では実行。

```
$ terraform init
$ terraform plan
$ terraform apply
```

5分くらいで完了しました。このサンプルでは、この後のcloud-initのパッケージ処理に時間がかかります。待てない場合は前述の通り、カスタムイメージを使いましょう。

インスタンスへのsshを通すよう、Load BalancerにNATを設定していますので、cloud-initの進捗は確認できます。

```
$ ssh -p 50000 yourname@yourvmss01.eastus2.cloudapp.azure.com
$ tail -f /var/log/cloud-init-output.log
Cloud-init v. 17.1 finished at Sun, 25 Mar 2018 10:41:40 +0000. Datasource DataSourceAzure [seed=/dev/sr0].  Up 611.51 seconds
```

ではWebサーバーにアクセスしてみましょう。

```
$ while true; do curl yourvmss01.eastus2.cloudapp.azure.com; sleep 1; done;
[Instance Name]: yourvmss01_2    [Zone]: 3
[Instance Name]: yourvmss01_0    [Zone]: 1
[Instance Name]: yourvmss01_2    [Zone]: 3
[Instance Name]: yourvmss01_1    [Zone]: 2
```

VMSSのインスタンスがゾーンに分散されたことが分かります。

では、このままスケールアウトしてみましょう。main.tfのazurerm_virtual_machine_scale_set.poc.sku.capacityを3から4にし、再度applyします。

```
[Instance Name]: yourvmss01_1    [Zone]: 2
[Instance Name]: yourvmss01_3    [Zone]: 1
[Instance Name]: yourvmss01_3    [Zone]: 1
[Instance Name]: yourvmss01_1    [Zone]: 2
[Instance Name]: yourvmss01_3    [Zone]: 1
```

ダウンタイムなしに、yourvmss01_3が追加されました。すこぶる簡単。