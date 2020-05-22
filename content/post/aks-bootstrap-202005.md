+++
Categories = ["Kubernetes"]
Tags = ["GitHub", "Azure","Kubernetes"]
date = "2020-05-21T13:05:00+09:00"
title = "Azure Kubernetes Service インフラ ブートストラップ開発フロー&コードサンプル 2020春版"

+++

## 何の話か

マネージドサービスなどではコマンド1発で作れるほどKubernetesクラスターの作成は楽になってきているのですが、運用を考えると他にもいろいろ仕込んでおきたいことがあります。監視であったり、ストレージクラスを用意したり、最近ではGitOps関連もあるでしょう。

ということで、最近わたしがAzure Kubernetes Service(AKS)の環境を作るコードを開発する際のサンプルコードとワークフローを紹介します。以下がポイントです。

* BootstrapとConfigurationを分割する
  * 環境構築、維持をまるっと大きなひとつの仕組みに押し込まず、初期構築(Bootstrap)とその後の作成維持(Configuration)を分割しています
  * 前者をTerraform、後者をFluxとHelm-Operatorによるプル型のGitOpsで実現します
    * FluxとHelm-Operatorは[Azure Arc](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/)でも採用されており、注目しています
  * 分割した理由はライフサイクルと責務に応じたリソースとツールの分離です
  * 前者はインフラチームに閉じ、後者はインフラチームとアプリチームの共同作業になりがちなので
  * どっちに置くか悩ましいものはあるのですが、入れた後に変化しがちなものはなるべくConfigurationでカバーするようにしてます
    * わたしの場合はPrometheusとか
* GitHubのプルリクを前提としたワークフロー
  * Bootstrapを開発する人はローカルでコーディング、テストしてからプルリク
  * プルリクによってCIのGitHub Actionsワークフローが走ります
  * terraformのformatとplanが実行され、結果がプルリクのコメントに追加されます
  * レビュワーはそれを見てmasterへのマージを判断します

## メインとなるHCLの概説

ちょっと長いのですが、AKSに関する[HCLコード](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/modules/aks/main.tf)は通して読まないとピンとこないと思うので解説します。全体像は[GitHub](https://github.com/ToruMakabe/aks-bootstrap-202005)を確認してください。

```hcl
data "azurerm_log_analytics_workspace" "aks" {
  name                = var.la_workspace_name
  resource_group_name = var.la_workspace_rg
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  kubernetes_version  = "1.18.2"
  location            = var.aks_cluster_location
  resource_group_name = var.aks_cluster_rg
  dns_prefix          = var.aks_cluster_name

  default_node_pool {
    name                = "default"
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    vnet_subnet_id      = var.aks_subnet_id
    availability_zones  = [1, 2, 3]
    node_count          = 2
    min_count           = 2
    max_count           = 5
    vm_size             = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    load_balancer_profile {
      managed_outbound_ip_count = 1
    }
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id
    }
    azure_policy {
      enabled = true
    }
  }

}

resource "azurerm_kubernetes_cluster_node_pool" "system" {
  name                  = "system"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vnet_subnet_id        = var.aks_subnet_id
  availability_zones    = [1, 2, 3]
  node_count            = 2
  vm_size               = "Standard_F2s_v2"
  node_taints           = ["CriticalAddonsOnly=true:NoSchedule"]
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks.id

  log {
    category = "kube-apiserver"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-controller-manager"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-scheduler"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "kube-audit"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "cluster-autoscaler"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = false

    retention_policy {
      days    = 0
      enabled = false
    }
  }
}

provider "kubernetes" {
  version = "~>1.11"

  load_config_file       = false
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_storage_class" "managed_premium_bind_wait" {
  metadata {
    name = "managed-premium-bind-wait"
  }
  storage_provisioner = "kubernetes.io/azure-disk"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    storageaccounttype = "Premium_LRS"
    kind               = "Managed"
  }
}

resource "kubernetes_cluster_role" "log_reader" {
  metadata {
    name = "containerhealth-log-reader"
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log", "events"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "log_reader" {
  metadata {
    name = "containerhealth-read-logs-global"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "containerhealth-log-reader"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "User"
    name      = "clusterUser"
    api_group = "rbac.authorization.k8s.io"
  }
}

provider "helm" {
  version = "~>1.2"

  kubernetes {
    load_config_file       = false
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "kubernetes_namespace" "flux" {
  count = var.enable_flux ? 1 : 0
  metadata {
    name = "flux"
  }
}

resource "helm_release" "flux" {
  count      = var.enable_flux ? 1 : 0
  name       = "flux"
  namespace  = "flux"
  repository = "https://charts.fluxcd.io/"
  chart      = "flux"
  version    = "1.3.0"

  set {
    name  = "helm.versions"
    value = "v3"
  }

  set {
    name  = "git.url"
    value = "git@github.com:${var.git_authuser}/${var.git_fluxrepo}"
  }

}

resource "helm_release" "helm_operator" {
  count      = var.enable_flux ? 1 : 0
  name       = "helm-operator"
  namespace  = "flux"
  repository = "https://charts.fluxcd.io/"
  chart      = "helm-operator"
  version    = "1.0.2"

  set {
    name  = "helm.versions"
    value = "v3"
  }

  set {
    name  = "git.ssh.secretName"
    value = "flux-git-deploy"
  }

}
```

以下は特記すべきリソースと設定、その背景などです。

* (data).azurerm_log_analytics_workspace.aks
  * Azure Monitorのワークスペースを指定します
  * ログはクラスター削除後も残しておきたいケースが多いので、AKSクラスターに合わせた動的な作成削除はしない方針です
* azurerm_kubernetes_cluster.aks.kubernetes_version
  * 目的に応じ、お好みのバージョンを
* azurerm_kubernetes_cluster.aks.default_node_pool
  * 既定のノードプールで、オートスケールを有効にしています
  * このサンプルでは、加えて後述するManaged Identityへ権限割当を行います
* azurerm_kubernetes_cluster.aks.identity
  * typeをSystemAssignedにしているため、別途サービスプリンシパルを作成、指定する必要はありません
  * 以前はサービスプリンシパルの作成と指定、管理が煩雑、グローバル同期の考慮など悩ましかったのですが、楽になりました
  * ただしAKS関連リソースが入るリソースグループ(MC_*)の外にあるリソースには、SystemAssigned指定で作られるManaged Identityから[操作する権限がない](https://docs.microsoft.com/ja-jp/azure/aks/use-managed-identity)ため、必要な場合はSystemAssignedではなく権限を持ったサービスプリンシパルを指定しましょう
    * もしくはSystemAssined指定で作成したManaged Identityに必要な権限を割り当てます
    * 例: AKSを既存の別リソースグループにあるVNetに参加させる場合に、オートスケール時にサブネット操作するための権限割当が必要([参考スクリプト](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/scripts/assign_role_mi.sh))
* azurerm_kubernetes_cluster.aks.addon_profile.azure_policy
  * OPAを利用したポリシー適用を有効化しています
  * 現時点でプレビュー機能なので、[リソースプロバイダーの有効化](https://docs.microsoft.com/ja-jp/azure/governance/policy/concepts/policy-for-kubernetes?toc=%2Fazure%2Faks%2Ftoc.json)も行ってください
* azurerm_kubernetes_cluster_node_pool.system
  * CoreDNSなどCritical Addonを分離するためにノードプールを分けています
  * 安定稼働が優先なのでオートスケール設定はしません
  * コストと[要件](https://docs.microsoft.com/ja-jp/azure/aks/use-system-pools#system-and-user-node-pools)のバランスから、VMはStandard_F2s_v2にしています
  * CriticalAddonsOnlyでtolerationしているPodだけがこのプールで動けるようにtaintしています
  * ただしCritical Addonがdefaultノードプールにスケジューリングされる可能性は残るので、厳密にしたい場合は合わせて[ノードプールのモード指定](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/scripts/update-mode-aks-nodepools.sh)、Critical Addonたちへ[nodeSelectorの指定](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/scripts/update-nodeselecter-system-deployments.sh)、[リスタート](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/scripts/restart-system-deployments.sh)が必要です
  * なお、この追加したノードプールのモードをsystem、defaultプールのモードをuserにすると、destroy時に追加したsystemノードプールを先に削除しに行ってしまい「systemモードのプールが最低1つは要るぞ」と怒られますので、destroy前にモードを[再設定](https://github.com/ToruMakabe/aks-bootstrap-202005/blob/master/src/scripts/update-mode-aks-nodepools-on-deletion.sh)しましょう
  * いずれこの流れはAKS APIとHCLで吸収できると期待しています
* azurerm_monitor_diagnostic_setting.aks
  * マスターコンポーネントのログをAzure Monitorに送るよう設定します
* kubernetes_storage_class.managed_premium_bind_wait
  * AZにクラスターノードを分散した場合、別のAZにあるPodとボリュームは関連付けできません
  * Podより先にボリュームが作られてしまうとPodのスケジューリングができなくなる恐れがあるので、Podのスケジューリングを待つStorageClassを作ります
* kubernetes_cluster_role.log_reader & kubernetes_cluster_role_binding.log_reader
  * Azure Monitorの[リアルタイムビュー機能](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-livedata-overview?toc=https%3A%2F%2Fdocs.microsoft.com%2Fja-jp%2Fazure%2Faks%2Ftoc.json&bc=https%3A%2F%2Fdocs.microsoft.com%2Fja-jp%2Fazure%2Fbread%2Ftoc.json)を使えるようにしています
* kubernetes_namespace.flux & helm_release.flux & helm_release.helm_operator
  * GitOpsのためにFluxとHelm-Operatorを導入しています
  * variable enable_fluxをfalseにすれば導入されません
  * ブートストラップ後に[Fluxの設定](https://github.com/ToruMakabe/aks-bootstrap-202005)を行ってください

## その他、ワークフローに関する説明など

長くなってしまったので、GitHubのリポジトリ[README](https://github.com/ToruMakabe/aks-bootstrap-202005)をご確認ください。えんじょい。
