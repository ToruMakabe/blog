+++
Categories = ["Azure"]
Tags = ["Azure", "Linux", "Fileshare"]
date = "2016-02-07T17:00:00+09:00"
title = "Linux on Azureでファイル共有する方法"

+++

## ファイル共有、あまりおすすめしないです
いきなりタイトルを否定しました。ロック。

さて、これからクラウド、というお客様に、よく聞かれる質問があります。それは「NFSとかの、ファイル共有使える?」です。頻出です。クラウド頻出質問選手権では、西東京予選で毎年ベスト8入りするレベルの強豪校です。

ですが**個人的には**あまりおすすめしません。クラウドはなるべく共有部分を減らして、スケーラブルに、かつ障害の影響範囲を局所化するべき、と考えるからです。特にストレージはボトルネックや広範囲な障害の要因になりやすい。障害事例が物語ってます。その代わりにオブジェクトストレージなど、クラウド向きの機能がおすすめです。

でも、全否定はしません。アプリの作りを変えられないケースもあるかと思います。

そこで、もしAzureでファイル共有が必要であれば、[Azure File Storage](https://azure.microsoft.com/ja-jp/documentation/articles/storage-introduction/)を検討してみてください。Azureのマネージドサービスなので、わざわざ自分でサーバたてて運用する必要がありません。楽。

対応プロトコルは、SMB2.1/3.0。LinuxからはNFSじゃなくSMBでつついてください。

使い方は公式ドキュメントを。

["Azure Storage での Azure CLI の使用"](https://azure.microsoft.com/ja-jp/documentation/articles/storage-azure-cli/#create-and-manage-file-shares)

["Linux で Azure File Storage を使用する方法"](https://azure.microsoft.com/ja-jp/documentation/articles/storage-how-to-use-files-linux/)

もうちょっと情報欲しいですね。補足のためにわたしも流します。

## Azure CLIでストレージアカウントを作成し、ファイル共有を設定
ストレージアカウントを作ります。fspocは事前に作っておいたリソースグループです。

    local$ azure storage account create tomakabefspoc -l "Japan East" --type LRS -g fspoc

ストレージアカウントの接続情報を確認します。必要なのはdata: connectionstring:の行にあるAccountKey=以降の文字列です。このキーを使ってshareの作成、VMからのマウントを行うので、控えておいてください。

    local$ azure storage account connectionstring show tomakabefspoc -g fspoc
    info:    Executing command storage account connectionstring show
    + Getting storage account keys
    data:    connectionstring: DefaultEndpointsProtocol=https;AccountName=tomakabefspoc;AccountKey=qwertyuiopasdfghjklzxcvbnm==
    info:    storage account connectionstring show command OK

shareを作成します。share名はfspocshareとしました。

    local$ azure storage share create -a tomakabefspoc -k qwertyuiopasdfghjklzxcvbnm== fspocshare

エンドポイントを確認しておきましょう。VMからのマウントの際に必要です。

    local$ azure storage account show tomakabefspoc -g fspoc
    [snip]
    data:    Primary Endpoints: file https://tomakabefspoc.file.core.windows.net/

## Linux * 2VMで共有
Ubuntuでやりますよ。SMBクライアントとしてcifs-utilsパッケージをインストールします。[Marketplace提供のUbuntu14.04LTS](https://azure.microsoft.com/ja-jp/marketplace/partners/canonical/ubuntuserver1404lts/)であれば、すでに入ってるはずです。

    fspocvm01:~$ sudo apt-get install cifs-utils
    
マウントポイントを作り、マウントします。接続先の指定はエンドポイント+share名で。usernameはストレージアカウント名。パスワードはストレージアカウントのキーです。
パーミッションは要件に合わせてください。

    fspocvm01:~$ sudo mkdir -p /mnt/fspoc
    fspocvm01:~$ sudo mount -t cifs //tomakabefspoc.file.core.windows.net/fspocshare /mnt/fspoc -o vers=3.0,username=tomakabefspoc,password=qwertyuiopasdfghjklzxcvbnm==,dir_mode=0777,file_mode=0777

マウント完了。確認用のファイルを作っておきます。

    fspocvm01:~$ echo "test" > /mnt/fspoc/test.txt
    fspocvm01:~$ cat /mnt/fspoc/test.txt
    test

2台目のVMでも同様のマウント作業を。

    fspocvm02:~$ sudo apt-get install cifs-utils
    fspocvm02:~$ sudo mkdir -p /mnt/fspoc
    fspocvm02:~$ sudo mount -t cifs //tomakabefspoc.file.core.windows.net/fspocshare /mnt/fspoc -o vers=3.0,username=tomakabefspoc,password=qwertyuiopasdfghjklzxcvbnm==,dir_mode=0777,file_mode=0777

1台目で作ったファイルが見えますね。

    fspocvm02:~$ ls /mnt/fspoc
    test.txt
    fspocvm02:~$ cat /mnt/fspoc/test.txt
    test

ファイルをいじりましょう。

    fspocvm02:~$ echo "onemoretest" >> /mnt/fspoc/test.txt
    fspocvm02:~$ cat /mnt/fspoc/test.txt
    test
    onemoretest

1台目から確認。

    fspocvm01:~$ cat /mnt/fspoc/test.txt
    test
    onemoretest
    
## ご利用は計画的に
2016/2月時点でAzure File Storageは最大容量:5TB/share、1TB/file、ストレージアカウントあたりの帯域:60MBytes/sという制約があります。これを超えるガチ共有案件では、[Lustre](https://azure.microsoft.com/en-us/marketplace/partners/intel/lustre-cloud-edition-evaleval-lustre-2-7/)など別の共有方法を検討してください。

なおファイルサーバ用途であれば、Azure File Storageではなく、OneDriveなどオンラインストレージSaaSに移行した方が幸せになれると思います。企業向けが使いやすくなってきましたし。運用から解放されるだけじゃなく、便利ですよ。