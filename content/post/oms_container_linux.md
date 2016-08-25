+++
Categories = ["Azure"]
Tags = ["Docker", "Azure", "OMS"]
date = "2016-08-25T16:00:00+09:00"
title = "OMSでLinuxコンテナのログを分析する"

+++

## OMS Container Solution for Linux プレビュー開始
OMS OMS Container Solution for Linuxのプレビューが[はじまりました](https://blogs.technet.microsoft.com/msoms/2016/08/24/announcing-public-preview-oms-container-solution-for-linux/)。OMSのログ分析機能は500MB/日のログ転送まで無料で使えるので、利用者も多いのではないでしょうか。

さて、このたびプレビュー開始したLinuxコンテナのログ分析機能、サクッと使えるので紹介します。まだプレビューなので、仕様が変わったらごめんなさい。

## 何ができるか、とその特徴
* Dockerコンテナに関わるログの収集と分析、ダッシュボード表示
  * 収集データの詳細 - [Containers data collection details](https://azure.microsoft.com/ja-jp/documentation/articles/log-analytics-containers/#containers-data-collection-details)
* 導入が楽ちん
  1. OMSエージェントコンテナを導入し、コンテナホスト上のすべてのコンテナのログ分析ができる
  2. コンテナホストに直接OMS Agentを導入することもできる

1がコンテナ的でいいですよね。実現イメージはこんな感じです。

![OMS Agent Installation Type](https://msdnshared.blob.core.windows.net/media/2016/08/3-OMS-082416.png)

これであれば、CoreOSのような「コンテナホストはあれこれいじらない」というポリシーのディストリビューションにも対応できます。

では試しに、1のやり口でUbuntuへ導入してみましょう。

## 手順
* OMSのログ分析機能を有効化しワークスペースを作成、IDとKeyを入手 ([参考](https://azure.microsoft.com/ja-jp/documentation/articles/log-analytics-get-started/))
  * Azureのサブスクリプションを持っている場合、"[Microsoft Azure を使用した迅速なサインアップ](https://azure.microsoft.com/ja-jp/documentation/articles/log-analytics-get-started/#microsoft-azure)"から読むと、話が早いです
* OMSポータルのソリューションギャラリーから、"Containers"を追加
* UbuntuにDockerを導入
  * [参考](https://docs.docker.com/engine/installation/linux/ubuntulinux/)
  * 現在、OMSエージェントが対応するDockerバージョンは 1.11.2までなので、たとえばUbuntu 16.04の場合は sudo apt-get install docker-engine=1.11.2-0~xenial とするなど、バージョン指定してください
* OMSエージェントコンテナを導入
  * 先ほど入手したOMSのワークスペースIDとKeyを入れてください

```
sudo docker run --privileged -d -v /var/run/docker.sock:/var/run/docker.sock -e WSID="your workspace id" -e KEY="your key" -h=`hostname` -p 127.0.0.1:25224:25224/udp -p 127.0.0.1:25225:25225 --name="omsagent" --log-driver=none --restart=always microsoft/oms
```

以上。これでOMSポータルからログ分析ができます。こんな感じで。

![Dashboard1](https://acom.azurecomcdn.net/80C57D/cdn/mediahandler/docarticles/dpsmedia-prod/azure.microsoft.com/en-us/documentation/articles/log-analytics-containers/20160824105310/containers-dash01.png)

![Dashboard2](https://acom.azurecomcdn.net/80C57D/cdn/mediahandler/docarticles/dpsmedia-prod/azure.microsoft.com/en-us/documentation/articles/log-analytics-containers/20160824105310/containers-dash02.png)

なんと簡単じゃありませんか。詳細が気になるかたは、[こちら](https://azure.microsoft.com/ja-jp/documentation/articles/log-analytics-containers/#containers-data-collection-details)から。

なお、フィードバック[熱烈歓迎](https://blogs.technet.microsoft.com/msoms/2016/08/24/announcing-public-preview-oms-container-solution-for-linux/)だそうです。