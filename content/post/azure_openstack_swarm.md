+++
Categories = ["Azure"]
Tags = ["Azure", "OpenStack", "Docker"]
date = "2015-12-19T00:01:00+09:00"
title = "OpenStackとAzureにDocker Swarmをかぶせてみた"

+++

## どこいってもいじられる
[OpenStack Advent Calendar 2015](http://www.adventar.org/calendars/968) 参加作品、19夜目のエントリです。

OpenStackの最前線から離れて3か月がたちました。OpenStackつながりな方にお会いするたび、マイルドなかわいがりをうけます。ほんとうにありがとうございます。仕事としては専門でなくなりましたが、ユーザ会副会長の任期はまだ残っているので、積極的にいじられに行く所存です。でも笑いながら蹴ったりするのはやめてください。

さて、毎年参加しているOpenStack Advent Calendarですが、せっかくだからいまの専門とOpenStackを組み合わせたいと思います。ここはひとつ、OpenStackとAzureを組み合わせて何かやってみましょう。

## 乗るしかないこのDockerウェーブに
どうせなら注目されている技術でフュージョンしたいですね。2015年を振り返って、ビッグウェーブ感が高かったのはなんでしょう。はい、Dockerです。Dockerを使ってOpenStackとAzureを組み合わせてみます。あまり難しいことをせず、シンプルにサクッとできることを。年末ですし、「正月休みにやってみっか」というニーズにこたえます。

ところでOpenStack環境はどうやって調達しましょう。ちょっと前までは身の回りに売るほどあったのですが。探さないといけないですね。せっかくなので日本のサービスを探してみましょう。

条件はAPIを公開していること。じゃないと、Dockerの便利なツール群が使えません。Linuxが動くサービスであれば、Docker環境をしみじみ手作業で夜なべして作れなくもないですが、嫌ですよね。正月休みは修行じゃなくて餅食って酒飲みたい。安心してください、わかってます。人力主義では、せっかくサクサク使えるDockerが台無しです。

あと、当然ですが個人で気軽にオンラインで契約できることも条件です。

そうすると、ほぼ一択。[Conoha](https://www.conoha.jp/)です。かわいらしい座敷童の["このは"](https://www.conoha.jp/conohadocs/?btn_id=top_footer_conotsu)がイメージキャラのサービスです。作っているのは手練れなOSSANたちですが。

では、AzureとConohaにDocker環境をサクッと作り、どちらにもサクッと同じコンテナを作る。もちろん同じCLIから。ということをしてみようと思います。

今回大活躍するDoker Machine、Swarmの説明はしませんが、関心のある方は[前佛さんの資料](http://www.slideshare.net/zembutsu/whats-new-aobut-docker-2015-network-and-orchestration)を参考にしてください。

## ローカル環境
* Mac OS X (El Capitan)
    * Docker Toolbox 1.9.1

ローカル、Azure、ConohaすべてのDocker環境はDocker Machineでサクッと作ります。
また、Swarmのマスタはローカルに配置します。

## いざ実行
まず、Docker Machineにクラウドの諸設定を食わせます。

Azure向けにサブスクリプションIDとCertファイルの場所を指定します。詳細は[ここ](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-docker-machine/)を。

    $ export AZURE_SUBSCRIPTION_ID=hoge-fuga-hoge-fuga-hoge
    $ export AZURE_SUBSCRIPTION_CERT=~/.ssh/yourcert.pem
    
Conoha向けにOpenStack関連の環境変数をセットします。

    $ export OS_USERNAME=yourname
    $ export OS_TENANT_NAME=yourtenantname
    $ export OS_PASSWORD=yourpass
    $ export OS_AUTH_URL=https://identity.tyo1.conoha.io/v2.0
    
次はローカルコンテナ環境を整えます。

Swarmコンテナを起動し、ディスカバリトークンを生成します。このトークンがSwarmクラスタの識別子です。

    $ docker-machine create -d virtualbox local
    $ eval "$(docker-machine env local)"
    $ docker run swarm create    
    Status: Downloaded newer image for swarm:latest
    tokentokentokentoken

このトークンは控えておきましょう。

ではSwarmのマスタをローカルに作ります。先ほど生成したトークン指定を忘れずに。

    $ docker-machine create -d virtualbox --swarm --swarm-master --swarm-discovery token://tokentokentokentoken head
 
 SwarmのエージェントをAzureに作ります。VMを作って、OSとDockerをインストールして、なんて不要です。Docker Machineがやってくれます。ここでもトークン指定を忘れずに。
    
    $ eval "$(docker-machine env head)"
    $ docker-machine create -d azure --swarm --swarm-discovery token://tokentokentokentoken worker-azure01 --azure-location "East Asia" worker-azure00
 
 Conohaにも同様に。
    
    $ docker-machine create -d openstack --openstack-flavor-name g-1gb --openstack-image-name vmi-ubuntu-14.04-amd64 --openstack-sec-groups "default,gncs-ipv4-all" --swarm --swarm-discovery token://tokentokentokentoken worker-conoha00
 
 さあ環境がサクッと出来上がりました。これ以降はSwarmクラスタ全体を操作対象にします。
    
    $ eval "$(docker-machine env --swarm head)"
    
 環境をチラ見してみましょう。
 
    $ docker info
    Containers: 4
    Images: 3
     Role: primary
     Strategy: spread
     Filters: health, port, dependency, affinity, constraint
     Nodes: 3
     head: 192.168.99.101:2376
      └ Containers: 2
      └ Reserved CPUs: 0 / 1
      └ Reserved Memory: 0 B / 1.021 GiB
      └ Labels: executiondriver=native-0.2, kernelversion=4.1.13-boot2docker, operatingsystem=Boot2Docker 1.9.1 (TCL 6.4.1); master : cef800b - Fri Dec 18 19:33:59 UTC 2015, provider=virtualbox, storagedriver=aufs
     worker-azure00: xxx.cloudapp.net:2376
      └ Containers: 1
      └ Reserved CPUs: 0 / 1
      └ Reserved Memory: 0 B / 1.721 GiB
      └ Labels: executiondriver=native-0.2, kernelversion=3.13.0-36-generic, operatingsystem=Ubuntu 14.04.1 LTS, provider=azure, storagedriver=aufs
     worker-conoha00: www.xxx.yyy.zzz:2376
      └ Containers: 1
      └ Reserved CPUs: 0 / 2
      └ Reserved Memory: 0 B / 1.019 GiB
      └ Labels: executiondriver=native-0.2, kernelversion=3.16.0-51-generic, operatingsystem=Ubuntu 14.04.3 LTS, provider=openstack, storagedriver=aufs
    CPUs: 4
    Total Memory: 3.761 GiB
    Name: 1234abcd

どこにどんな環境が作られたかが分かりますね。出力結果の4行目"Strategy: spread"を覚えておいてください。

ではコンテナを作ってみましょう。Nginxコンテナ三連星です。どの環境に作るか、という指定はしません。

    $ for i in `seq 1 3`; do docker run -d -p 80:80 nginx; done
    
どんな具合でしょう。

    $ docker ps
    CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                                NAMES
    9cc2f5594fa5        nginx               "nginx -g 'daemon off"   5 seconds ago       Up 4 seconds        192.168.99.101:80->80/tcp, 443/tcp   head/goofy_goldberg
    b9d54d794a85        nginx               "nginx -g 'daemon off"   32 seconds ago      Up 31 seconds       www.xxx.yyy.zzz:80->80/tcp, 443/tcp   worker-conoha00/clever_chandrasekhar
    19e9d0e229a2        nginx               "nginx -g 'daemon off"   45 seconds ago      Up 42 seconds       zzz.yyy.xxx.www:80->80/tcp, 443/tcp    worker-azure00/reverent_bhaskara

Nginxコンテナがきれいに散らばっているのが分かります。これは先ほど覚えた"Strategy: spread"が効いているからです。StrategyはSwarmのコンテナ配置ポリシーで、speradを指定すると散らしにいきます。Strategyをbinpackにしておけば、ノードを埋めようとします。埋まったら他、です。randomであれば、ランダムに。

まだシンプルですが、今後このStrategyやリソース管理が賢くなると、「ローカルが埋まったら、リモートを使う」とか、使い道が広がりそうですね。最近Docker社が買収した[Tutum](https://www.tutum.co/)との関係、今後どう進化していくのか、注目です。

## ツールから入るハイブリッドクラウドも、またよし
ハイブリッドクラウドはまだ言葉先行です。まだクラウドを使ってない、使いこなしていない段階でツールの話だけが先行することも多いです。ナイフとフォークしか使ったことのない人が、お箸を使う和食や中華を選ぶ前に「どんなお箸がいいかねぇ」と議論している感じ。僕は、そうじゃなくて、その前に食べたいもの = クラウドを選びましょうよ、というスタンスでした。

でも、コンテナ+Dockerって、お箸に弁当ついてきたような感じなんですよね。お箸が使える人であれば、弁当持ち込める場所さえ確保すればいい。インパクトでかいです。ちょっと考えを改めました。

もちろん、だからクラウドは何でもいい、と言っているわけではありません。弁当持ち込みとしても、スペースが広い、個室で静か、お茶がうまい、お茶がタダ、揚げたてのから揚げを出してくれる、などなど、特徴は出てくるでしょう。APIを公開していないような「持ち込みやめて」のクラウドは、先々心配ですが。

簡単 = 正義です。簡単であれば使う人が増えて、要望が増えて、育ちます。かっちり感は後からついてくる。もしDockerで複数のクラウド環境を簡単に使いこなせるようになるのであれば、順番が逆ではありますが、お箸、Dockerというツールから入るのもいいかもしれません。

まずは開発、検証環境など、リスク低いところから試して慣れていくのがおすすめです。触っていくうちに、いろいろ見えてくるでしょう。Dockerはもちろんですが、それぞれのクラウドの特徴も。

OpenStackもAzureも、特徴を活かし、うまく使いこなしてほしいと思っております。