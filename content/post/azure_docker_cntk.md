+++
Categories = ["Azure"]
Tags = ["Azure", "Docker", "Deep Learning", "CNTK"]
date = "2016-04-17T10:30:00+09:00"
title = "AzureとDockerでDeep Learning(CNTK)環境をサク作する"

+++

## 気軽に作って壊せる環境を作る
Deep Learning環境設計のお手伝いをする機会に恵まれまして。インフラおじさんはDeep Learningであれこれする主役ではないのですが、ちょっとは中身を理解しておきたいなと思い、環境作ってます。

試行錯誤するでしょうから、萎えないようにデプロイは自動化します。

## 方針

* インフラはAzure Resource Manager Templateでデプロイする
    * Linux (Ubuntu 14.04) VM, 仮想ネットワーク/ストレージ関連リソース
* CNTKをビルド済みのdockerリポジトリをDocker Hubに置いておく
    * Dockerfileの元ネタは[ここ](https://github.com/Microsoft/CNTK/tree/master/Tools/docker)
        * GPUむけもあるけどグッと我慢、今回はCPUで
    * Docker Hub上のリポジトリは [torumakabe/cntk-cpu](https://hub.docker.com/r/torumakabe/cntk-cpu/)
* ARM TemplateデプロイでVM Extensionを仕込んで、上物のセットアップもやっつける
    * docker extensionでdocker engineを導入
    * custom script extensionでdockerリポジトリ(torumakabe/cntk-cpu)をpull
* VMにログインしたら即CNTKを使える、幸せ

## 使い方

Azure CLIでARM Templateデプロイします。WindowsでもMacでもLinuxでもOK。

リソースグループを作ります。

    C:\Work> azure group create CNTK -l "Japan West"
    
ARMテンプレートの準備をします。テンプレートはGithubに置いておきました。

* [azuredeploy.json](https://github.com/ToruMakabe/CNTK/blob/master/deploy_singlenode/azuredeploy.json)
    * 編集不要です
* [azuredeploy.parameters.json](https://github.com/ToruMakabe/CNTK/blob/master/deploy_singlenode/azuredeploy.parameters.sample.json)
    * テンプレートに直で書かきたくないパラメータです
    * fileUris、commandToExecute以外は、各々で
    * fileUris、commandToExecuteもGist読んでdocker pullしているだけなので、お好みで変えてください
    * ファイル名がazuredeploy.parameters."sample".jsonなので、以降の手順では"sample"を外して読み替えてください
    
うし、デプロイ。

    C:\Work> azure group deployment create CNTK dep01 -f .\azuredeploy.json -e .\azuredeploy.parameters.json
    
10分くらい待つと、できあがります。VMのパブリックIPを確認し、sshしましょう。

docker engine入ってますかね。

    yourname@yournamecntkr0:~$ docker -v
    Docker version 1.11.0, build 4dc5990
    
CNTKビルド済みのdockerイメージ、pullできてますかね。

    yourname@yournamecntkr0:~$ docker images
    REPOSITORY            TAG                 IMAGE ID            CREATED             SIZE
    yournamebe/cntk-cpu   latest              9abab8a76543        9 hours ago         2.049 GB
    
問題なし。ではエンジョイ Deep Learning。

    yourname@yournamecntkr0:~$ docker run -it torumakabe/cntk-cpu
    root@a1234bc5d67d:/cntk#
    
CNTKの利用例は、[Github](https://github.com/Microsoft/CNTK/tree/master/Examples)にあります。

## 今後の展開
インフラおじさんは、最近Linuxむけに[Previewがはじまった](https://azure.microsoft.com/ja-jp/blog/announcing-support-of-linux-vm-on-azure-batch-service/)Azure Batchと、このエントリで使った仕掛けを組み合わせて、大規模並列Deep Learning環境の自動化と使い捨て化を企んでいます。

これだけ簡単に再現性ある環境を作れるなら、常時インフラ起動しておく必要ないですものね。使い捨てでいいです。

もちろんdockerやGPUまわりの性能など別の課題にぶつかりそうですが、人間がどれだけ楽できるかとのトレードオフかと。