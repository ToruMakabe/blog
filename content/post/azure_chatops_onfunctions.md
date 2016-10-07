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

[AZChatOpsSample](https://github.com/ToruMakabe/AZChatOpsSample)


## おおまかな流れ

手順書つらいのでポイントだけ。

* SlackのSlash CommandとIncoming Webhookを作る

  * 流れは氏の[元ネタ](http://fabriccontroller.net/chatops-deploy-and-manage-complete-environments-on-azure-using-slack/)と同じ

* ARM TemplateでFunction Appをデプロイ

  * Github上のDeployボタンからでもいいですが、パラメータファイルを作っておけばCLIで楽に繰り返せます

  * パラメータファイルのサンプルは[sample.azuredeploy.parameters.json](https://github.com/ToruMakabe/AZChatOpsSample/blob/master/sample.azuredeploy.parameters.json)です。GUIでデプロイするにしても、パラメータの意味を理解するためにざっと読むと幸せになれると思います

  * Function AppのデプロイはGithubからのCIです。クローンしたリポジトリとブランチを指定してください

  * Azure Automationのジョブ実行権限を持つサービスプリンシパルが必要です (パラメータ SUBSCRIPTION_ID、TENANT_ID、CLIENT_ID、CLIENT_SECRET で指定)

  * Azure Automationについて詳しく説明しませんが、Slackから呼び出すRunbookを準備しておいてください。そのAutomationアカウントと所属するリソースグループを指定します

  * 作成済みのSlack関連パラメータを指定します

* ARM Templateデプロイ後にkuduのデプロイメントスクリプトが走るので、しばし待つ(Function Appの設定->継続的インテグレーションの構成から進捗が見えます)  

* デプロイ後、Slash Commandで呼び出すhttptrigger function(postJob)のtokenを変更

  * kuduでdata/Functions/secrets/postJob.jsonの値を、Slackが生成したSlash Commandのtokenに書き換え

* Slack上で、Slash Commandのリクエスト先URLを変更 (例: https://yourchatops.azurewebsites.net/api/postJob?code=TokenTokenToken)

* ファンクションが動いたら、Slackの指定チャンネルでSlash Commandが打てるようになる

  * /runbook [runbook名] [parm1] [parm2] [parm...]

  * パラメータはrunbook次第

* Runbookの進捗はIncoming Webhookでslackに通知される

  * Runbookのステータスが変わったときに通知

## よもやま話

* SlackのSlash Commandは、3秒以内に返事を返さないとタイムアウトします。なのでいくつか工夫しています。

  * ファンクションはトリガーされるまで寝ています。また、5分間動きがないとこれまた寝ます(cold状態になる)。寝た子を起こすのには時間がかかるので、Slackの3秒ルールに間に合わない可能性があります。

  * Azure FunctionsのWebコンソールログが無活動だと30分で停止するので、coldに入る条件も30分と誤解していたのですが、正しくは5分。ソースは[ここ](https://github.com/Azure/azure-webjobs-sdk-script/issues/529)。

  * そこで、4分周期でTimer Triggerし、postJobにダミーPOSTするpingFuncを作りました。

  * ファンクションのコードに更新があった場合、リロード処理が走ります。リロード後、またしてもトリガーを待って寝てしまうので、コード変更直後にSlash Commandを打つとタイムアウトする可能性大です。あせらずpingまで待ちましょう。

  * Azure Functionsはまだプレビューなので、[議論されているとおり](https://github.com/Azure/azure-webjobs-sdk-script/issues/529)改善の余地が多くあります。期待しましょう。
