+++
Categories = ["Azure"]
Tags = ["Azure", "PaintsChainer", "NVIDIA"]
date = "2017-02-03T18:00:00+09:00"
title = "Azure N-SeriesでPaintsChainerを動かす"

+++

## PaintsChainer面白い

クラスメソッドさんのDevelopers.IOでのエントリ["PaintsChainerをAmazon EC2で動かしてみた"](http://dev.classmethod.jp/cloud/paintschainer-on-ec2/)が、とても面白いです。

畳みこみニューラルネットワークを駆使して白黒線画に色付けしちゃうPaintsChainerすごい。EC2のGPUインスタンスでさくっと動かせるのもいいですね。

せっかくなのでAzureでもやってみようと思います。AzurerはN-Series & NVIDIA-Dockerのサンプルとして、Azurerでない人はUbuntuでPaintsChainerを動かす参考手順として見ていただいてもいいかと。

## 試した環境
* 米国中南部リージョン
* Standard NC6 (6 コア、56 GB メモリ、NVIDIA Tesla K80)
* Ubuntu 16.04
* NSGはSSH(22)の他にHTTP(80)を受信許可

## 導入手順

### NVIDIA Tesla driversのインストール
マイクロソフト公式ドキュメントの通りに導入します。

[Set up GPU drivers for N-series VMs](https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-linux-n-series-driver-setup)

### Dockerのインストール
Docker公式ドキュメントの通りに導入します。

[Get Docker for Ubuntu](https://docs.docker.com/engine/installation/linux/ubuntu/)

### NVIDIA Dockerのインストール
GitHub上のNVIDIAのドキュメント通りに導入します。

[NVIDIA Docker](https://github.com/NVIDIA/nvidia-docker)

ここまでの作業に問題がないか、確認します。

```
$ sudo nvidia-docker run --rm nvidia/cuda nvidia-smi
Using default tag: latest
latest: Pulling from nvidia/cuda
8aec416115fd: Pull complete
[...]
Status: Downloaded newer image for nvidia/cuda:latest
Fri Feb  3 06:43:18 2017
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 367.48                 Driver Version: 367.48                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  Tesla K80           Off  | 86BF:00:00.0     Off |                    0 |
| N/A   34C    P8    33W / 149W |      0MiB / 11439MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID  Type  Process name                               Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

### PaintsChainer-Dockerのインストール
Liam Jones氏が公開している[PaintsChainer-Docker](https://github.com/liamjones/PaintsChainer-Docker)を使って、PaintsChanierコンテナーを起動します。ポートマッピングはコンテナーホストの80番とコンテナーの8000番です。

```
$ sudo nvidia-docker run -p 80:8000 liamjones/paintschainer-docker
```

## PaintsChainerを使ってみる

VMのパブリックIP、ポート80番にアクセスすると、先ほどコンテナーで起動したPaintsChainerのページが開きます。クラウディアさんの白黒画像ファイルで試してみましょう。

![結果](https://raw.githubusercontent.com/ToruMakabe/Images/master/paintschainer_cloudia.png "Cloudia")

PaintsChainer、すごいなぁ。
クラウディアさん、おなか寒そうだけど。
