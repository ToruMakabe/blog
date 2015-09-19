---
date: "2014-03-23T00:00:00+09:00"
slug: "swift-upload"
title: OpenStack Swiftへのファイル分割アップロード
category: Tips
tags: [OpenStack, Swift]
---
### Swiftへ、ファイルを分割してアップロードできる
今週偶然にも、何度か質問されたり、TwitterのTLにこの話題が流れてたり。もしかしたら世の関心が高い話題かもしれないので、まとめておきます。

### アップロード形式は大きく3つ -- そのまま、DLO、SLO
1. そのまま、ファイルに手を加えずにアップロードします。この場合、ファイルサイズの上限は5GBです。5GBを超えるファイルをアップロードする場合、後述のDLO、SLOどちらかの形式でファイルを分割する必要があります。
2. DLO(Dynamic Large Object)形式。ファイルを任意のサイズに分割し、Swift上で1つのファイルに見せかけます。「指定のコンテナ/疑似フォルダ下にあるファイルを結合する」というルールなのでアップロード手順がシンプルです。また、後からのセグメント追加/削除が容易です。
3. SLO(Static Large Object)形式。ファイルを任意のサイズに分割し、Swift上で1つのファイルに見せかけます。分割セグメントファイルのハッシュ値をリストした、マニフェストファイルの作成が必要です。Swift上でハッシュのチェックが行われるため、データの完全性がDLOより高いです。また、セグメントを任意のコンテナに分散できるため、負荷分散の手段が増えます。

### 動きを見てみよう
環境は以下の通り。

* HP Public Cloud US-West Region
* Swift Clientを動かすCompute Node -- standard.large / ubuntu 12.04
* Swift CLI -- 2.0.3
* 約900MBあるubuntu desktopのisoファイルをアップロード

#### そのままアップロード
    $time swift -v upload mak-cont ./ubuntu-13.10-desktop-amd64.iso --object-name non-seg.iso
    No handlers could be found for logger "keystoneclient.httpclient"
    non-seg.iso
    
    real	0m24.557s
    user	0m12.617s
    sys	0m11.197s

ハンドラーが無いとか怒られましたが、別事案なので気にせずにいきましょう。そのまま送ると、25秒くらい。

    $curl -H "X-Auth-Token: hoge" -I https://region-a.geo-1.objects.hpcloudsvc.com/v1/fuga/mak-cont/non-seg.iso
    
    HTTP/1.1 200 OK
    Content-Length: 925892608
    Content-Type: application/x-iso9660-image
    Accept-Ranges: bytes
    Last-Modified: Sun, 23 Mar 2014 01:16:53 GMT
    Etag: 21ec41563ff34da27d4a0b56f2680c4f
    X-Timestamp: 1395537413.17419
    X-Object-Meta-Mtime: 1381950899.000000
    X-Trans-Id: txfee207024dd04bd599292-00532e3c5e
    Date: Sun, 23 Mar 2014 01:43:58 GMT

ヘッダはこんな感じ。

#### DLO形式でアップロード
    $time swift -v upload mak-cont ./ubuntu-13.10-desktop-amd64.iso --object-name dlo.iso --segment-size 104857600
    No handlers could be found for logger "keystoneclient.httpclient"
    dlo.iso segment 0
    dlo.iso segment 5
    dlo.iso segment 1
    dlo.iso segment 2
    dlo.iso segment 3
    dlo.iso segment 4
    dlo.iso segment 8
    dlo.iso segment 7
    dlo.iso segment 6
    dlo.iso
    
    real	0m11.568s
    user	0m7.960s
    sys	0m4.448s

Swift CLIが各セグメントを100MBに分割してアップロードしています。並列でアップロードしているので、
分割しない場合とくらべて転送時間は半分以下です。転送時間を重視するなら、ファイルサイズが5GB以下でも分割は有用です。

    $curl -H "X-Auth-Token: hoge" -I https://region-a.geo-1.objects.hpcloudsvc.com/v1/fuga/mak-cont/dlo.iso
    HTTP/1.1 200 OK
    Content-Length: 925892608
    X-Object-Meta-Mtime: 1381950899.000000
    Accept-Ranges: bytes
    X-Object-Manifest: mak-cont_segments/dlo.iso/1381950899.000000/925892608/104857600/
    Last-Modified: Sun, 23 Mar 2014 01:22:25 GMT
    Etag: "7085388575f90df99531b60f9d9b1291"
    X-Timestamp: 1395537755.32458
    Content-Type: application/x-iso9660-image
    X-Trans-Id: txd90ac8f8f6a64c749de2f-00532e3c6f
    Date: Sun, 23 Mar 2014 01:44:15 GMT

X-Object-Manifestという属性が、セグメント化したファイルの置き場所を指しています。

#### SLO形式でアップロード
    $time swift -v upload mak-cont ./ubuntu-13.10-desktop-amd64.iso --object-name slo.iso --segment-size 104857600 --use-slo
    No handlers could be found for logger "keystoneclient.httpclient"
    slo.iso segment 3
    slo.iso segment 7
    slo.iso segment 1
    slo.iso segment 4
    slo.iso segment 8
    slo.iso segment 0
    slo.iso segment 5
    slo.iso segment 2
    slo.iso segment 6
    slo.iso
    
    real	0m12.039s
    user	0m8.189s
    sys	0m4.820s

転送時間はDLOと同等です。Swift CLIを使う場合は --use-sloオプションを指定するだけなので、データ完全性の観点からSLOがおすすめです。

    $curl -H "X-Auth-Token: hoge" -I https://region-a.geo-1.objects.hpcloudsvc.com/v1/fuga/mak-cont/slo.iso
    HTTP/1.1 200 OK
    Content-Length: 925892608
    X-Object-Meta-Mtime: 1381950899.000000
    Accept-Ranges: bytes
    Last-Modified: Sun, 23 Mar 2014 01:24:08 GMT
    Etag: "7085388575f90df99531b60f9d9b1291"
    X-Timestamp: 1395537859.11815
    X-Static-Large-Object: True
    Content-Type: application/x-iso9660-image
    X-Trans-Id: tx6cec436f525f4eb89dcfc-00532e3c7b
    Date: Sun, 23 Mar 2014 01:44:27 GMT

X-Static-Large-Object属性がTrueになりました。

参考情報
- [Swift Documentaion -- Large Object Support](http://docs.openstack.org/developer/swift/overview_large_objects.html)
- [HP Cloud Object Storage API Reference](https://docs.hpcloud.com/api/object-storage/#large_objects-jumplink-span)