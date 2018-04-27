+++
Categories = ["Azure"]
Tags = ["Azure", "Terraform"]
date = "2018-04-27T17:00:00+09:00"
title = "TerraformでAzureのシークレットを受け渡す(ACI/AKS編)"

+++

## 動機
システム開発、運用の現場では、しばしばシークレットの受け渡しをします。代表例はデータベースの接続文字列です。データベース作成時に生成した接続文字列をアプリ側で設定するのですが、ひとりでコピペするにせよ、チームメンバー間で受け渡すにせよ、めんどくさく、危険が危ないわけです。

* いちいちポータルやCLIで接続文字列を出力、コピーして、アプリの設定ファイルや環境変数にペーストしなければいけない
  * めんどくさいし手が滑る
* データベース管理者がアプリ開発者に接続文字列を何らかの手段で渡さないといけない
  * メールとかチャットとかファイルサーバーとか勘弁
* もしくはアプリ開発者にデータベースの接続文字列が読める権限を与えなければいけない
  * 本番でも、それやる？
* kubernetes(k8s)のSecretをいちいちkubectlを使って作りたくない
  * Base64符号化とか、うっかり忘れる

つらいですね。シークレットなんて意識したくないのが人情。そこで、Terraformを使った解決法を。

## シナリオ
Azureでコンテナーを使うシナリオを例に紹介します。ACI(Azure Container Instances)とAKS(Azure Container Service - k8s)の2パターンです。

* Nodeとデータストアを組み合わせた、[Todoアプリケーション](https://github.com/ToruMakabe/ImpressAzureBookNode)
* コンテナーイメージは[Docker Hub](https://hub.docker.com/r/torumakabe/nodetodo/)にある
* コンテナーでデータストアを運用したくないので、データストアはマネージドサービスを使う
* データストアはCosmos DB(MongoDB API)
* Cosmos DBへのアクセスに必要な属性をTerraformで参照し、接続文字列(MONGO_URL)を作る
  * 接続文字列の渡し方はACI/AKSで異なる
    * ACI
      * コンテナー作成時に環境変数として接続文字列を渡す
    * AKS
      * k8sのSecretとして接続文字列をストアする
      * コンテナー作成時にSecretを参照し、環境変数として渡す

## 検証環境

* Azure Cloud Shell
  * Terraform v0.11.7
  * Terraformの認証はCloud Shell組み込み
* Terraform Azure Provider v1.4
* Terraform kubernetes Provider v1.1
* AKS kubernetes 1.9.6

## ACIの場合
ざっと以下の流れです。

1. リソースグループ作成
2. Cosmos DBアカウント作成
3. ACIコンテナーグループ作成 (Cosmos DB属性から接続文字列を生成)

var.で参照している変数は、別ファイルに書いています。

[main.tf]
```
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "${var.resource_group_location}"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "your-cosmos-db-${random_integer.ri.result}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  offer_type          = "Standard"
  kind                = "MongoDB"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }

  geo_location {
    location          = "${azurerm_resource_group.rg.location}"
    failover_priority = 0
  }

  geo_location {
    location          = "${var.failover_location}"
    failover_priority = 1
  }
}

resource "azurerm_container_group" "aci-todo" {
  name                = "aci-todo"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  ip_address_type     = "public"
  dns_name_label      = "yourtodo"
  os_type             = "linux"

  container {
    name   = "hw"
    image  = "torumakabe/nodetodo"
    cpu    = "1"
    memory = "1.5"
    port   = "8080"

    environment_variables {
      "MONGO_URL" = "mongodb://${azurerm_cosmosdb_account.db.name}:${azurerm_cosmosdb_account.db.primary_master_key}@${azurerm_cosmosdb_account.db.name}.documents.azure.com:10255/?ssl=true"
    }
  }
}
```

containerのenvironment_variablesブロックでCosmos DBの属性を参照し、接続文字列を生成しています。簡単ですね。これで接続文字列コピペ作業から解放されます。

## AKS
AKSの場合、流れは以下の通りです。

1. リソースグループ作成
2. Cosmos DBアカウント作成
3. AKSクラスター作成 
4. k8s Secretを作成 (Cosmos DB属性から接続文字列生成)
5. k8s Secretをコンテナーの環境変数として参照し、アプリをデプロイ

[main.tf]
```
resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "${var.resource_group_location}"
}

resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "your-cosmos-db-${random_integer.ri.result}"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  offer_type          = "Standard"
  kind                = "MongoDB"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }

  geo_location {
    location          = "${azurerm_resource_group.rg.location}"
    failover_priority = 0
  }

  geo_location {
    location          = "${var.failover_location}"
    failover_priority = 1
  }
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "yourakstf"
  location            = "${azurerm_resource_group.rg.location}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  dns_prefix          = "yourakstf"
  kubernetes_version  = "1.9.6"

  linux_profile {
    admin_username = "${var.admin_username}"

    ssh_key {
      key_data = "${var.key_data}"
    }
  }

  agent_pool_profile {
    name            = "default"
    count           = 3
    vm_size         = "Standard_B2ms"
    os_type         = "Linux"
    os_disk_size_gb = 30
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }
}

provider "kubernetes" {
  host = "${azurerm_kubernetes_cluster.aks.kube_config.0.host}"

  client_certificate     = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)}"
  client_key             = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)}"
  cluster_ca_certificate = "${base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)}"
}

resource "kubernetes_secret" "cosmosdb_secret" {
  metadata {
    name = "cosmosdb-secret"
  }

  data {
    MONGO_URL = "mongodb://${azurerm_cosmosdb_account.db.name}:${azurerm_cosmosdb_account.db.primary_master_key}@${azurerm_cosmosdb_account.db.name}.documents.azure.com:10255/?ssl=true"
  }
}
```

Cosmos DB、AKSクラスターを作ったのち、kubernetesプロバイダーを使ってSecretを登録しています。複数のプロバイダーを組み合わせられる、Terraformの特長が活きています。

そしてアプリのデプロイ時に、登録したSecretを指定します。ここからはkubernetesワールドなので、kubectlなどを使います。マニフェストは以下のように。

[todo.yaml]
```
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: todoapp
spec:
  selector:
    matchLabels:
      app: todoapp
  replicas: 2
  template:
    metadata:
      labels:
        app: todoapp
    spec:
      containers:
        - name: todoapp
          image: torumakabe/nodetodo
          ports:
            - containerPort: 8080
          env:
            - name: MONGO_URL
              valueFrom:
                secretKeyRef:
                  name: cosmosdb-secret
                  key: MONGO_URL
---
apiVersion: v1
kind: Service
metadata:
  name: todoapp
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: todoapp
```

シークレットの中身を見ることなく、コピペもせず、もちろんメールやチャットやファイルも使わず、アプリからCosmos DBへ接続できました。

シークレットに限らず、Terraformの属性参照、変数表現は強力ですので、ぜひ活用してみてください。数多くの[Azureリソース](https://www.terraform.io/docs/providers/azurerm/)が対応しています。