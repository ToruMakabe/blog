+++
Categories = ["Azure"]
Tags = ["Azure","Kubernetes","Terraform"]
date = "2020-10-06T16:00:00+09:00"
title = "Azure Kubernetes Serviceの推奨メトリックアラートをTerraoformで設定する"

+++

## 何の話か

Azure Monitor for containersで、Azure Kubernetes Service(AKS)の推奨メトリックアラートを設定できるようになりました。どのアラート設定もよく使われているもので、検討の価値があります。

>[Azure Monitor for containers からの推奨メトリック アラート (プレビュー)](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-metric-alerts)

ドキュメントではAzure PortalとAzure Resource Managerテンプレートによる設定手順が紹介されているのですが、アラートを有効にする部分のみです。推奨メトリックアラートを既存環境で試すだけならこれでもいいのですが、いずれクラスター作成や再現時に合わせて設定したくなるはずです。そこで、Terraformでクラスター作成と同時にサクっと設定できるようにしてみましょう。

*(注)2020年10月時点のやり口です*

## サンプルコードで出来ること

[Gist](https://gist.github.com/ToruMakabe/e7787218eee07a003143849d0855ae59)にサンプルコードを公開しました。お楽しみください。

このサンプルコードで下記のリソース作成、設定ができます。せっかくなのでAKSとAzure Monitor for containersの組み合わせで取得、監視、分析できる他のメトリック、ログ関連の設定も入れておきました。

* AKSクラスターの作成
  * マネージドIDの有効化
  * Azure Monitor for containersの有効化
    * Log Analyticsワークスペースは既存を指定
* [AKSカスタムメトリックの有効化](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-update-metrics)
* 推奨メトリックアラートの設定
  * OOM Killed Containers
  * Average container working set memory %
* [マスターノードログのLog Analytics Workspaceへの転送](https://docs.microsoft.com/ja-jp/azure/aks/view-master-logs)
* [ログ、イベント、メトリックのライブデータ表示設定](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-livedata-setup)

## コード解説

ポイントだけ抜き出して解説します。

### OMS Agent向けマネージドIDに対するAzure Monitorメトリック発行権限の付与

Azure Monitor for containersは各ノードにエージェント(OMS Agent)を配布し、ログやメトリックを収集します。メトリックとして扱うデータも、まずログ形式でLog Analyticsワークスペースに送信し、その上でメトリック化やアラート作成を[行います](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-log-alerts)。Kustoクエリによる柔軟な指定が可能です。

しかしLog Analyticsワークスペースでは、インデクシングなどデータを使えるようになるまでの前処理が必要で、アラートまでのタイムラグが大きくなりがちです。アラートや迅速な分析の用途ではLog Analyticsワークスペースではなく、多次元メトリック(MDM - Multi-Dimensional Metrics)データ構造で、時系列データストアをバックに持つAzure Monitorメトリックストアが適しているのは間違いありません。

>[Azure Monitor のメトリック](https://docs.microsoft.com/ja-jp/azure/azure-monitor/platform/data-platform-metrics)

このような背景があり、Azure Monitor for containerのOMS Agentから、メトリックデータをLog Analyticsワークスペースだけでなく、Azure MonitorメトリックストアへAKSカスタムメトリックとして送れるようになりました。

そこで、アラート設定のためにまずカスタムメトリックを有効化しましょう。Azure Monitorのメトリックは各リソース単位で管理されており、書き込み権限の設定が必要です。つまりAKSクラスターリソースに対し、OMS Agentからメトリックを発行できるようにロールを付与しなければいけません。

サンプルではAKSクラスターをマネージドIDを使うよう設定しているので、OMS Agetアドオン向けに作成されるマネージドIDに対し、Monitoring Metrics Publisherロールを付与しています。

```
resource "azurerm_role_assignment" "aks_metrics" {
  scope                = azurerm_kubernetes_cluster.sample.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.sample.addon_profile.0.oms_agent.0.oms_agent_identity.0.object_id
}
```

なおAzure Monitor for containersのOMS Agentのコードは[公開](https://github.com/microsoft/Docker-Provider)されています。お楽しみください。

### メトリック発行閾値の設定

Azure Monitor for containersで設定されるメトリックの中には、OMS Agentがメトリック送信の要否を閾値によって[判断するもの](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-metric-alerts#alert-rules-overview)があります。つまり閾値を超えない場合には、Azure Monitorへメトリックが送られません。

よって、アラートだけでなく分析にもメトリックを使いたいケースでは、Azure Monitorで設定したアラート閾値よりも、OMS Agentの送信閾値を低くします。

現在、コンテナーのcpuExceededPercentage、memoryRssExceededPercentage、memoryWorkingSetExceededPercentageの送信閾値を[変更可能](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-metric-alerts#configure-alertable-metrics-in-configmaps)です。OMS AgentはConfigMapを読み込み、既定値を上書きします。

下記はmemoryWorkingSetExceededPercentageを既定値の95%から80%に変更する例です。


```
resource "kubernetes_config_map" "oms_agent" {
  depends_on = [azurerm_role_assignment.aks_metrics]
  metadata {
    name      = "container-azm-ms-agentconfig"
    namespace = "kube-system"
  }

  data = {
    schema-version                           = "v1"
    config-version                           = "ver1"
    alertable-metrics-configuration-settings = <<EOT
[alertable_metrics_configuration_settings.container_resource_utilization_thresholds]
    container_memory_working_set_threshold_percentage = 80.0
EOT
  }

  // Waiting for omsagent restart & custom metrics preparation
  provisioner "local-exec" {
    command = "sleep 180"
  }
}
```

サンプルコードではHCLのheredocに設定を埋め込みました。ComfigMapの元ネタは[GitHub上](https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml)にあります。

ちなみに、このComfigMapではログ収集の除外Namespaceを設定したり、Prometheusメトリックの[スクレーピング設定](https://docs.microsoft.com/ja-jp/azure/azure-monitor/insights/container-insights-prometheus-integration)などもできるので、合わせて活用しましょう。

なおConfigMap作成後に、やや長めですが180秒スリープさせています。カスタムメトリックが有効になるのを待つためです。カスタムメトリックがまだ有効になっていない状態で後述のアラート設定を行うと、「カスタムメトリックが見つからない」とエラーになるため、それを回避します。

### アラート設定

アラートのアクショングループはクラスター作成とライフサイクルが違うケースが多いと思いますので、既存のものを読み込みます。

```
data "azurerm_monitor_action_group" "sample" {
  resource_group_name = var.alert_actiongroup_rg_name
  name                = var.alert_actiongroup_name
}
```

そしてアラートの設定です。以下はOOM Killed Containersの数を頻度1分、ウインドウ5分の平均で評価し、0より大きければアラートアクションを呼び出すサンプルです。

```
resource "azurerm_monitor_metric_alert" "aks_oom_killed_container_count" {
  depends_on          = [kubernetes_config_map.oms_agent]
  name                = "oomKilledContainerCount"
  resource_group_name = azurerm_resource_group.sample.name
  scopes              = [azurerm_kubernetes_cluster.sample.id]
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Insights.Container/pods"
    metric_name      = "oomKilledContainerCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0


    dimension {
      name     = "kubernetes namespace"
      operator = "Include"
      values   = ["*"]
    }

    dimension {
      name     = "controllerName"
      operator = "Include"
      values   = ["*"]
    }

  }

  action {
    action_group_id = data.azurerm_monitor_action_group.sample.id
  }
}
```

コード化するにあたってアラート設定値の元ネタが欲しくなりますが、[GitHub](https://github.com/microsoft/Docker-Provider/tree/ci_prod/alerts/recommended_alerts_ARM)上にあります。Azure Resource ManagerテンプレートのJSON形式ですので、そこから属性と値を拾ってHCLに書き換えましょう。閾値や頻度、評価ウインドウを好みに変えてもいいでしょう。

サンプルコードには2つのみ書きましたが、他にも9つの推奨アラートがあります。ぜひ必要なものを加えてみて下さい。
