+++
Categories = ["Azure"]
Tags = ["Azure", "ChatOps", "Functions", "Slack"]
date = "2016-10-07T17:00:00+09:00"
title = "SlackとAzure FunctionsでChatOpsする"

+++

## Azure Functionsでやってみよう

Azure上でChatOpsしたい、と相談をいただきました。

AzureでChatOpsと言えば、Auth0のSandrino Di Mattia氏が作った素敵な[サンプル](http://fabriccontroller.net/chatops-deploy-and-manage-complete-environments-on-azure-using-slack/)があります。

![Azure Runスラッシュ](http://fabriccontroller.net/static/chatops-how-this-works.png.pagespeed.ce.lN444drUKd.png "from fabriccontroller.net")

素晴らしい。これで十分、という気もしますが、実装のバリエーションがあったほうが後々参考になる人も多いかなと思い、Web App/Web JobをAzure Functionsで置き換えてみました。

## SlackからRunbookを実行できて、何がうれしいか

* 誰がいつ、どんな文脈でRunbookを実行したかを可視化する
* CLIやAPIをRunbookで隠蔽し、おぼえることを減らす
* CLIやAPIをRunbookで隠蔽し、できることを制限する

## ブツ

Githubに上げておきました。

[AZChatOpsSmaple](https://github.com/ToruMakabe/AZChatOpsSample)

## おおまかな流れ

手順書はつらいのでポイントだけ。

* SlackのスラッシュコマンドとIncoming Webhookを作る
  * 流れはSandino氏の[元ネタ](http://fabriccontroller.net/chatops-deploy-and-manage-complete-environments-on-azure-using-slack/)と同じ
* ARM TemplateでFunction Appをデプロイ
  * Github上のDeployボタンからでもいいですが、パラメータファイルを作っておけばCLIで楽に繰り返せます
  * パラメータファイルのサンプルは[sample.azuredeploy.parameters.json](https://github.com/ToruMakabe/AZChatOpsSample/blob/master/sample.azuredeploy.parameters.json)です、GUIでデプロイする場合も、パラメータの意味を理解するためにざっと読むと幸せになれると思います
  * Function AppのデプロイはGithubからCIするので、クローンしたリポジトリとブランチを指定してください
  * Azure Automationのジョブ実行権限を持つサービスプリンシパルが必要です (パラーメータ SUBSCRIPTION_ID、TENANT_ID、CLIENT_ID、CLIENT_SECRET で指定)
  * Azure Automationについては触れませんが、Slackから呼び出すRunbookを準備してください
* ARM Templateデプロイ後にkuduのデプロイメントスクリプトが走るので、しばし待つ(Function Appの設定->継続的インテグレーションの構成から進捗が見えます)  
* デプロイ後、スラッシュコマンドで呼び出すhttptrigger function(postJob)のtokenを変更
  * kuduでdata/Functions/secrets/postJob.jsonの値を、Slackが生成したスラッシュコマンドのtokenに書き換え
* Slack スラッシュコマンドのリクエスト先URLを変更 (例: https://yourchatops.azurewebsites.net/api/postJob?code=TokenTokenToken)

* Functionが動いたら、Slackの指定チャンネルでスラッシュコマンドが打てるようになる
  * /runbook [runbook名] [parm1] [parm2] [parm...]
  * パラメータはrunbook次第
* Runbookの進捗はIncoming Webhookでslackに通知される
  * Runbookのステータスが変わったときに通知

## よもやま話

* Slackのスラッシュコマンドは、3秒以内に返事を返さないとタイムアウトします。なのでいくつか工夫しています。
  * functionはTriggerされるまで寝ています。また、5分間動きがないとこれまた寝ます(cold状態になる)。寝た子を起こすのには時間がかかるので、Slackの3秒ルールに間に合わない可能性があります。
  * FunctionsのWebコンソールログが30分で停止するので30分と誤解していたのですが、正しくは5分。ソースは[ここ](https://github.com/Azure/azure-webjobs-sdk-script/issues/529)。
  * そこで、4分周期でTimer Triggerし、postJobにダミーPOSTするpingFuncを作りました。
  * Functionに更新があった場合、リロードが走ります。リロード後も寝てしまうので、コード変更直後はタイムアウトしてしまうかもしれません。あせらずpingまで待ちましょう。
  * Azure Functionsはまだプレビューなので、[議論されているとおり](https://github.com/Azure/azure-webjobs-sdk-script/issues/529)改善の余地が多くあります。期待しましょう。