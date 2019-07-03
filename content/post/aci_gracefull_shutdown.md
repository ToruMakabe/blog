+++
Categories = ["Azure"]
Tags = ["ACI", "Azure"]
date = "2019-07-03T23:00:00+09:00"
title = "Azure Cotainer InstancesのGraceful Shutdown事情"

+++

## 何の話か

Azure Container Instances(ACI)はサクッとコンテナーを作れるところが幸せポイントですが、停止処理どうしてますか。クライアントとのコネクションをぶっちぎってもいい、何かしらの書き込み処理が中途半端に終わっても問題ない、という人でなければ読む価値があります。

ACIはKubernetesで言うところのポッドを1つから使えるサービスです。概念や用語もKubernetesに似ています。家族や親戚という感じではありますが、"Kubernetesである"とは明言されていないので、その違いは意識しておいたほうがいいでしょう。この記事ではコンテナーの停止、削除処理に絞って解説します。

## Kubernetesのポッド停止処理

Kubernetesのポッド停止については、[@superbrothers](https://twitter.com/superbrothers)さんの素晴らしい解説記事があります。

> [Kubernetes: 詳解 Pods の終了](https://qiita.com/superbrothers/items/3ac78daba3560ea406b2)

書籍 [みんなのDocker/Kubernetes](https://gihyo.jp/book/2019/978-4-297-10461-0)のPart2 第3章でも最新の動向を交えて説明されています。しっかり理解したい人に、おすすめです。

ざっくりまとめると、ポッドをGraceful Shutdownする方法は次の2つです。

* PreStop処理を書いて、コンテナー停止に備える
* コンテナー停止時に送られるシグナルを、適切に扱う

ACIでは現在PreStop処理を書けません。なので、シグナルをどう扱うかがポイントです。

## DockerのPID 1問題

シグナルハンドリングの前に、DockerのPID 1問題について触れておきます。

> [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)

Unix/LinuxではプロセスIDの1番はシステム起動時にinit(systemd)へ割り当てられます。そして親を失ったプロセスの代理親となったり、終了したプロセスを管理テーブルから消したりします。いわゆるゾンビプロセスのお掃除役も担います。

しかしDockerでは、コンテナーではじめに起動したプロセスにPID 1が割り当てられます。それはビルド時にDockerfileのENTRYPOINTにexec形式で指定したアプリであったり、シェル形式であれば/bin/sh -cだったりします。

この仕様には、次の課題があります。

* コンテナーにゾンビプロセスのお掃除をするinitがいない
* [docker stop](https://docs.docker.com/engine/reference/commandline/stop/)を実行するとPID 1のプロセスに対してSIGTERMが、一定時間の経過後(既定は10秒)にSIGKILLが送られる。PID 1はLinuxで特別な扱いであり、SIGTERMのハンドラーがない場合、それを無視する。ただしinitの他はSIGKILLを無視できない。つまりPID 1で動いたアプリは待たされた挙句、強制終了してしまう。また、転送しなければ子プロセスにSIGTERMが伝わらない

前者が問題になるかは、コンテナーでどれだけプロセスを起動するかにもよります。いっぽうで後者は、PID 1となるアプリで意識してSIGTERMを処理しなければ、常に強制終了されることを意味します。穏やかではありません。

## 解決の選択肢

シグナルハンドリングについては、解決の選択肢がいくつかあります。

1. SIGTERMを受け取って、終了処理をするようアプリを書く
2. PID 1で動く擬似initを挟み、その子プロセスとしてアプリを動かす
3. PID 1で動く擬似initを挟み、その子プロセスとしてアプリを動かす (シグナル変換)

Docker APIを触れる環境であれば、docker run時に[--initオプション](https://docs.docker.com/engine/reference/run/#specify-an-init-process)をつければ擬似init([tini](https://github.com/krallin/tini))をPID 1で起動できます。ですがACIはコンテナーの起動処理を抽象化しているため、ユーザーから--initオプションを指定できません。なので別の方法で擬似initを挟みます。

## それぞれのやり方と動き

ではそれぞれのやり方と動きを見てみましょう。シグナルの送られ方がわかるように、Goで簡単なアプリを作りました。

```
package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	sigs := make(chan os.Signal, 1)
	done := make(chan bool, 1)

	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGQUIT)

	go func() {
		sig := <-sigs
		log.Println(sig)
		done <- true
	}()

	log.Println("awaiting signal")
	<-done
	log.Println("exiting")
}
```

SIGTERMかSIGQUITを受け取ったら、受け取ったシグナルの種類をログに書いて終了します。

### SIGTERMを意識できていない場合

まずは何もしなかった時の動きを見るため、SIGTERMを無視するようにアプリを書き換えます。

```
signal.Notify(sigs, syscall.SIGQUIT)
```

以下のDockerfileでコンテナーをビルドします。終わったらレジストリにpushしておきます。

```
ARG GO_VERSION=1.12.6
FROM golang:${GO_VERSION}-alpine AS build-stage
RUN apk add --no-cache git
WORKDIR /src
COPY ./go.mod ./
RUN go mod download
COPY . .
RUN go build -o /goapp main.go

FROM alpine:3.9
COPY --from=build-stage /goapp /
CMD ["/goapp"]
```

ではACIにデプロイしましょう。コンテナー停止後もログを見たいので、Azure Monitorへログを送るオプションも指定します。

```
$ az container create -g YOUR-RG -n YOUR-CONTAINER-GROUP --image YOUR-REGISTRY/handle-signal:1.0.0 --log-analytics-workspace YOUR-WORKSPACE-ID --log-analytics-workspace-key YOUR-WORKSPACE-KEY
```

できあがったら、PIDを確認します。

```
$ az container exec -g YOUR-RG -n YOUR-CONTAINER-GROUP --exec-command ps
PID   USER     TIME  COMMAND
    1 root      0:00 /goapp
   10 root      0:00 ps
```

アプリがPID 1です。ではコンテナーを止めます。

```
$ az container stop -g YOUR-RG -n YOUR-CONTAINER-GROUP
```

Azure Monitorに送られたログを見てみます。

```
2019/07/03 00:49:52 awaiting signal
```

コンテナーが停止した後、待てど暮らせどこのままです。つまり送られたSIGTERMを受け取らず、SIGKILLで強制終了したと考えられます。そう書いたのですから、期待通りの動きです。

### SIGTERMを処理する

ではアプリをSIGTERMを受け取るように変更します。

```
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGQUIT)
```

ひとつ前と同じDockerfileでビルドし、レジストリにpushします。そして、コンテナーを実行、停止します。ログはどう出力されたでしょうか。

```
2019/07/03 00:57:42 awaiting signal
2019/07/03 00:59:17 terminated
2019/07/03 00:59:17 exiting
```

うまくSIGTERMを受け取れたようです。

### 擬似initを挟む

擬似initとして、Yelpの開発した[dumb-init](https://github.com/Yelp/dumb-init)を使ってみましょう。あとで触れますが、シグナルを変換できる優れものです。

dumb-initを仕込むよう、Dockerfileを変更します。build-stageは同じです。

```
FROM alpine:3.9
RUN apk add --no-cache dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
COPY --from=build-stage /goapp /
CMD ["/goapp"]
```

このイメージを動かすと、PIDはこのように割り当てられます。

```
$ az container exec -g YOUR-RG -n YOUR-CONTAINER-GROUP --exec-command ps
PID   USER     TIME  COMMAND
    1 root      0:00 /usr/bin/dumb-init -- /goapp
    5 root      0:00 /goapp
   11 root      0:00 /bin/sh
   15 root      0:00 ps
```

PID 1はdumb-initに割り当てられました。このコンテナーを停止すると、SIGTERMはdumb-initに送られます。

```
2019/07/03 01:13:36 awaiting signal
2019/07/03 01:18:46 terminated
2019/07/03 01:18:46 exiting
```

そして、SIGTERMがdumb-initからアプリに伝搬されたことがわかります。

### 擬似initを挟む (シグナル変換)

自分が作るアプリであればSIGTERMを適切に扱うよう書けばいいのですが、製品やコミュニティで配布されているソフトウェアをコンテナーに入れる場合は注意が必要です。ソフトウェアによってはSIGTERMをGraceful Shutdownの合図としないものもあります。たとえば、[NGINX](http://nginx.org/en/docs/control.html)はSIGTERMを強制終了(Fast Shutdown)のシグナルとして扱います。SIGQUITがGraceful Shutdown向けです。

そのような場合は、dumb-initのシグナル変換機能が役立ちます。コンテナーのビルド時にオプションを指定します。

```
FROM alpine:3.9
RUN apk add --no-cache dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--rewrite", "15:3", "--"]
COPY --from=build-stage /goapp /
CMD ["/goapp"]
```

これで、docker stop時に送られるSIGTERM(15)を、SIGQUIT(3)に変換できます。ではコンテナーを動かし、止めます。

```
2019/07/03 01:19:40 awaiting signal
2019/07/03 01:21:04 quit
2019/07/03 01:21:04 exiting
```

アプリは変換後のSIGQUITを受け取っています。

なお、すべてのパターンで同じですが、ACIではコンテナーを削除(delete)した場合も、停止(stop)時と同様にSIGTERMが送られます。

## Windowsの場合

これまでの例はLinuxですが、Windowsの場合はコンテナー停止時にアプリへCTRL_SHUTDOWN_EVENTが送られます。ただしイベント発行から5秒後に強制終了が走るため注意が必要です。5秒は固定値です。値を変えたい場合、コンテナー作成時にレジストリーを編集する[ワークアラウンド](https://github.com/moby/moby/issues/25982#issuecomment-426441183)があります。

なおWindowsコンテナーの仕様に影響力を持つKubernetes Windows-SIGでは、コンテナーランタイムのDocker EEからCRI-ContainerDへの移行など、まだ大きなテーマが議論され、対応中です。過渡期であることを意識しておきましょう。

> [Windows node support - V1.Pod](https://github.com/kubernetes/enhancements/blob/master/keps/sig-windows/20190103-windows-node-support.md#v1pod)

> [Supporting CRI-ContainerD on Windows](https://github.com/kubernetes/enhancements/blob/master/keps/sig-windows/20190424-windows-cri-containerd.md)

## まとめ

ACIで動かすアプリを行儀よく止めたいなら、停止時のシグナル処理を意識しましょう。
