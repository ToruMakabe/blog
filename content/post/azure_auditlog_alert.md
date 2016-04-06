+++
Categories = ["Azure"]
Tags = ["Azure", "Automation"]
date = "2016-04-06T17:00:00+09:00"
title = "Azureの監査ログアラートからWebhookの流れで楽をする"

+++

## 監査ログからアラートを上げられるようになります
Azureの監査ログからアラートを上げる機能のプレビューが[はじまりました](https://azure.microsoft.com/ja-jp/blog/new-features-for-azure-alerts-and-autoscale/)。これ、地味ですが便利な機能です。日々の運用に効きます。

## どんな風に使えるか
ルールに合致した監査ログが生成された場合、メール通知とWebhookによる自動アクションができます。可能性無限大です。

たとえば、「特定のリソースグループにVMが生成された場合、そのVMに対し強制的にログ収集エージェントをインストールし、ログを集める」なんてことができます。

これは「生産性を上げるため、アプリ開発チームにVMの生成は委任したい。でもセキュリティなどの観点から、ログは集めておきたい」なんてインフラ担当/Opsの課題に効きます。開発チームに「VM生成時には必ず入れてね」とお願いするのも手ですが、やはり人間は忘れる生き物ですので、自動で適用できる仕組みがあるとうれしい。

これまでは監視用のVMを立てて、「新しいVMがあるかどうか定期的にチェックして、あったらエージェントを叩き込む」なんてことをしていたわけですが、もうそのVMは不要です。定期的なチェックも要りません。アラートからアクションを実現する仕組みを、Azureがマネージドサービスとして提供します。

## 実装例
例としてこんな仕組みを作ってみましょう。

* 西日本リージョンのリソースグループ"dev"にVMが作成されたら、自動的にメール通知とWebhookを実行
* WebhookでAzure AutomationのRunbook Jobを呼び出し、OMS(Operations Management Suite)エージェントを該当のVMにインストール、接続先OMSを設定する
* OMSでログ分析

## 準備
以下の準備ができているか確認します。

* Azure Automation向けADアプリ、サービスプリンシパル作成
* サービスプリンシパルへのロール割り当て
* Azure Automationのアカウント作成
* Azure Automation Runbook実行時ログインに必要な証明書や資格情報などの資産登録
* Azure Automation Runbookで使う変数資産登録 (Runbook内でGet-AutomationVariableで取得できます。暗号化もできますし、コードに含めるべきでない情報は、登録しましょう)
* OMSワークスペースの作成

もしAutomationまわりの作業がはじめてであれば、下記記事を参考にしてください。とてもわかりやすい。

**[勤務時間中だけ仮想マシンを動かす（スケジュールによる自動起動・停止）](http://qiita.com/sengoku/items/1c3994ac8a2f0f0e88c5)**

## Azure Automation側の仕掛け
先にAutomationのRunbookを作ります。アラート設定をする際、RunbookのWebhook URLが必要になるので。

ちなみにわたしは証明書を使ってログインしています。資格情報を使う場合はログインまわりのコードを読み替えてください。

    param ( 
        [object]$WebhookData		  
    )

    if ($WebhookData -ne $null) {  
        $WebhookName    =   $WebhookData.WebhookName
        $WebhookBody    =   $WebhookData.RequestBody  
        $WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody)
           
        $AlertContext = [object]$WebhookBody.context
        
        $SPAppID = Get-AutomationVariable -Name 'SPAppID'
	    $Tenant = Get-AutomationVariable -Name 'TenantID'
	    $OMSWorkspaceId = Get-AutomationVariable -Name 'OMSWorkspaceId'
        $OMSWorkspaceKey = Get-AutomationVariable -Name 'OMSWorkspaceKey'
	    $CertificationName = Get-AutomationVariable -Name 'CertificationName'
	    $Certificate = Get-AutomationCertificate -Name $CertificationName
	    $CertThumbprint = ($Certificate.Thumbprint).ToString()    
    
	    $null = Login-AzureRmAccount -ServicePrincipal -TenantId $Tenant -CertificateThumbprint $CertThumbprint -ApplicationId $SPAppID   
    
	    $resourceObj = Get-AzureRmResource -ResourceId $AlertContext.resourceId
        $VM = Get-AzureRmVM -Name $resourceObj.Name -ResourceGroupName $resourceObj.ResourceGroupName
    
        $Settings = @{"workspaceId" = "$OMSWorkspaceId"}
        $ProtectedSettings = @{"workspaceKey" = "$OMSWorkspaceKey"}
    
        if ($VM.StorageProfile.OsDisk.OsType -eq "Linux") {  
            Set-AzureRmVMExtension -ResourceGroupName $AlertContext.resourceGroupName -Location $VM.Location -VMName $VM.Name -Name "OmsAgentForLinux" -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "OmsAgentForLinux" -TypeHandlerVersion "1.0" -Settings $Settings -ProtectedSettings $ProtectedSettings;
        }
        elseif ($VM.StorageProfile.OsDisk.OsType -eq "Windows")
        {
            Set-AzureRmVMExtension -ResourceGroupName $AlertContext.resourceGroupName -Location $VM.Location -VMName $VM.Name -Name "MicrosoftMonitoringAgent" -Publisher "Microsoft.EnterpriseCloud.Monitoring" -ExtensionType "MicrosoftMonitoringAgent" -TypeHandlerVersion "1.0" -Settings $Settings -ProtectedSettings $ProtectedSettings;
        }
	    else
	    {
		    Write-Error "Unknown OS Type."
	    }
    }
    else 
    {
        Write-Error "This runbook is meant to only be started from a webhook." 
    }
    
    
### Azure 監査ログアラート側の仕掛け
Powershellでアラートルールを作ります。実行アカウントの権限に気をつけてください。

    PS C:\work> $actionEmail = New-AzureRmAlertRuleEmail -CustomEmail yourname@example.com
    
    PS C:\work> $actionWebhook = New-AzureRmAlertRuleWebhook -ServiceUri https://abcdefgh.azure-automation.net/webhooks?token=your_token
    
    PS C:\work> Add-AzureRmLogAlertRule -Name createdVM -Location "Japan West" -ResourceGroup dev -OperationName Microsoft.Compute/virtualMachines/write -Status Succeeded  -SubStatus Created -TargetResourceGroup dev -Actions $actionEmail,$actionWebhook


以上。これで"dev"リソースグループにVMが作られた場合、自動でOMSエージェントがインストールされ、ログ収集がはじまります。


なお、メールも飛んできますので、うっとおしくなったらメール通知はアクションから外すか、ルールでさばいてくださいね。