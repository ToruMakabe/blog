+++
Categories = ["Azure"]
Tags = ["Azure", "Vagrant", "Docker"]
date = "2016-05-13T18:00:00+09:00"
title = "VagrantとDockerによるAzure向けOSS開発・管理端末のコード化"

+++

## 端末だってコード化されたい
Infrastructure as Codeは特に騒ぐ話でもなくなってきました。このエントリは、じゃあ端末の開発環境やツール群もコード化しようという話です。結論から書くと、VagrantとDockerを活かします。超絶便利なのにAzure界隈ではあまり使われてない印象。もっと使われていいのではと思い、書いております。

## 解決したい課題
こんな悩みを解決します。

* WindowsでOSS開発環境、Azure管理ツールのセットアップをするのがめんどくさい
* WindowsもMacも使っているので、どちらでも同じ環境を作りたい
* サーバはLinuxなので手元にもLinux環境欲しいけど、Linuxデスクトップはノーサンキュー
* 2016年にもなって長いコードをVimとかEmacsで書きたくない
* Hyper-VとかVirtualboxで仮想マシンのセットアップと起動、後片付けをGUIでするのがいちいちめんどくさい
* 仮想マシン起動したあとにターミナル起動->IP指定->ID/Passでログインとか、かったるい
* Azure CLIやTerraformなどクラウド管理ツールの進化が頻繁でつらい(月一回アップデートとか)
* でもアップデートのたびに超絶便利機能が追加されたりするので、なるべく追いかけたい
* 新メンバーがチームに入るたび、セットアップが大変
* 不思議とパソコンが生えてくる部屋に住んでおり、セットアップが大変
* 毎度作業のどこかが抜ける、漏れる、間違う 人間だもの

## やり口
VagrantとDockerで解決します。

* Windows/Macどちらにも対応しているVirtualboxでLinux仮想マシンを作る
* Vagrantでセットアップを自動化する
* Vagrantfile(RubyベースのDSL)でシンプルに環境をコード化する
* Vagrant Puttyプラグインを使って、Windowsでもsshログインを簡素化する
* 公式dockerイメージがあるツールは、インストールせずコンテナを引っ張る
* Windows/MacのいまどきなIDEなりエディタを使えるようにする

## セットアップ概要
簡単す。

1. Virtualboxを[インストール](https://www.virtualbox.org/)
2. Vagrantを[インストール](https://www.vagrantup.com/downloads.html)
3. Vagrant Putty Plugin(vagrant-multi-putty)を[インストール](https://github.com/nickryand/vagrant-multi-putty) #Windowsのみ。Puttyは別途入れてください
4. 作業フォルダを作り、Vagrant ファイルを書く

## サンプル解説
OSSなAzurerである、わたしのVagrantfileです。日々環境に合わせて変えてますが、以下は現時点でのスナップショット。

```
# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

$bootstrap=<<SCRIPT

#Common tools
sudo apt-get update
sudo apt-get -y install wget unzip jq

#Docker Engine
sudo apt-get -y install apt-transport-https ca-certificates
sudo apt-get -y install linux-image-extra-$(uname -r)
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo sh -c "echo deb https://apt.dockerproject.org/repo ubuntu-trusty main > /etc/apt/sources.list.d/docker.list"
sudo apt-get update
sudo apt-get -y purge lxc-docker
sudo apt-cache policy docker-engine
sudo apt-get -y install docker-engine=1.11.1-0~trusty
sudo gpasswd -a vagrant docker
sudo service docker restart

#Docker Machine
sudo sh -c "curl -L https://github.com/docker/machine/releases/download/v0.7.0/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine && chmod +x /usr/local/bin/docker-machine"

#Azure CLI
echo "alias azure='docker run -it --rm -v \\\$HOME/.azure:/root/.azure -v \\\$PWD:/data -w /data microsoft/azure-cli:latest azure'" >> $HOME/.bashrc

#Terraform
echo "alias terraform='docker run -it --rm -v \\\$PWD:/data -w /data hashicorp/terraform:0.6.14'" >> $HOME/.bashrc

#Packer
echo "alias packer='docker run -it --rm -v \\\$PWD:/data -w /data hashicorp/packer:latest'" >> $HOME/.bashrc

#nodebrew
curl -L git.io/nodebrew | perl - setup
echo 'export PATH=$HOME/.nodebrew/current/bin:$PATH' >> $HOME/.bashrc
$HOME/.nodebrew/current/bin/nodebrew install-binary 5.9.1
$HOME/.nodebrew/current/bin/nodebrew use 5.9.1

#Python3
wget -qO- https://bootstrap.pypa.io/get-pip.py | sudo -H python3.4

SCRIPT

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # Every Vagrant virtual environment requires a box to build off of.

  config.vm.box = "ubuntu/trusty64"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.

  config.vm.network "private_network", ip: "192.168.33.10"

  config.vm.provider "virtualbox" do |vb|
     vb.customize ["modifyvm", :id, "--memory", "2048"]
  end

  config.vm.provision :shell, inline: $bootstrap, privileged: false

end
```
$bootstrap=<<SCRIPT から SCRIPT が、プロビジョニングシェルです。初回のvagrant up時とvagrant provision時に実行されます。

### Common tools
 一般的なツールをaptでインストールします。wgetとかjqとか。
 
### Docker Engine & Machine
この後前提となるDockerをインストール。Dockerのバージョンは1.11.1を明示しています。Dockerは他への影響が大きいので、バージョンアップは慎重めの方針です。
 
### Azure CLI
インストールせずに[MS公式のDockerイメージ](https://hub.docker.com/r/microsoft/azure-cli/)を引っ張ります。なのでalias設定だけ。
-v オプションで、ホストLinuxとコンテナ間でデータを共有します。CLIが使う認証トークン($HOME/.azure下)やCLI実行時に渡すjsonファイル(作業ディレクトリ)など。詳細は後ほど。
また、azureコマンド発行ごとにコンテナが溜まっていくのがつらいので、--rmで消します。
 
### Terraform & Packer
Azure CLIと同様です。Hashicorpが[公式イメージ](https://hub.docker.com/u/hashicorp/)を提供しているので、それを活用します。
方針はlatest追いですが、不具合があればバージョンを指定します。たとえば、現状Terraformのlatestイメージに不具合があるので、0.6.14を指定しています。
-v オプションもAzure CLIと同じ。ホストとコンテナ間のファイルマッピングに使います。

なお、公式とはいえ他人のイメージを使う時には、Dockerfileの作りやビルド状況は確認しましょう。危険がデンジャラスですし、ENTRYPOINTとか知らずにうっかり使うと途方に暮れます。
 
### nodebrew
nodeのバージョンを使い分けるため。セットアップ時にv5.9.1を入れています。Azure Functions開発向け。
 
### Python3
Ubuntu 14.04では標準がPython2なので別途入れてます。Azure Batch向け開発でPython3使いたいので。

みなさん他にもいろいろあるでしょう。シェルなのでお好みで。
 
さて、ここまでがプロビジョニング時の処理です。以降の"Vagrant.configure～"は仮想マシンの定義で、難しくありません。ubuntu/trusty64(14.04)をboxイメージとし、IPやメモリを指定し、先ほど定義したプロビジョニング処理を指しているだけです。
 
## どれだけ楽か
では、環境を作ってみましょう。Vagrantfileがあるフォルダで
 
```
vagrant up
```
 
仮想マシンが作成されます。初回はプロビジョニング処理も走ります。
 
できましたか。できたら、
 
```
vagrant putty
```
 
はい。Puttyが起動し、ID/Passを入れなくてもsshログインします。破壊力抜群。わたしはこの魅力だけでTeraterm(Terraformではない)からPuttyに乗り換えました。ちなみにMacでは、vagrant sshで済みます。
 
あとはプロビジョニングされたLinuxを使って楽しんでください。そして、必要なくなったら or 作り直したくなったら
 
```
vagrant destroy
```
 
綺麗さっぱりです。仮想マシンごと消します。消さずにまた使う時は、vagrant haltを。
 
なお、vagrant upしたフォルダにあるファイルは、Virtualboxの共有フォルダ機能で仮想マシンと共有されます。shareとかいう名のフォルダを作って、必要なファイルを放り込んでおきましょう。その場合、仮想マシンのUbuntuからは/vagrant/shareと見えます。双方向で同期されます。
 
わたしは長いコードを書くときは、Windows/Mac側のIDEなりエディタを使って、実行は仮想マシンのLinux側、という流れで作業しています。

ちなみに、改行コードの違いやパーミッションには気を付けてください。改行コードはLFにする癖をつけておくと幸せになれます。パーミッションは全開、かつ共有領域では変えられないので、問題になるときは仮想マシン側で/vagrant外にコピーして使ってください。パーミッション全開だと怒られる認証鍵など置かないよう、注意。
 
また、Dockerコンテナを引っ張るAzure CLI、Terraform、Packerの注意点。
 
* 初回実行時にイメージのPullを行うので、帯域の十分なところでやりましょう
* サンプルでは -v $PWD:/data オプションにて、ホストのカレントディレクトリをコンテナの/dataにひもづけています。そして、-w /data にて、コンテナ内ワーキングディレクトリを指定しています。コマンドの引数でファイル名を指定したい場合は、実行したいファイルがあるディレクトリに移動して実行してください
    * (例) azure group deployment create RG01 DEP01 -f ./azuredeploy.json -e ./azuredeploy.parameters.json

## Bash on Windowsまで待つとか言わない
「WindowsではOSSの開発や管理がしにくい。Bash on Windowsが出てくるまで待ち」という人は、待たないで今すぐGoです。思い立ったが吉日です。繰り返しますがVagrantとDocker、超絶便利です。

インフラのコード化なんか信用ならん！という人も、まず今回紹介したように端末からはじめてみたらいかがでしょう。激しく生産性上がると思います。

夏近し、楽して早く帰ってビール呑みましょう。