+++
Categories = ["Azure"]
Tags = ["Aqua", "Azure", "Container"]
date = "2019-08-09T13:00:00+09:00"
title = "Azure Container Registry TasksでAqua MicroScannerを自動実行する"

+++

## 何の話か

コンテナーイメージに脆弱性のあるパッケージが含まれないかチェックしてくれるAqua MicroScannerですが、Azure Container Registry(ACR)のACR Tasks ビルド時でも実行できるとうれしいですよね。その手順をまとめます。

@ehotinger の[ブログ](https://ehotinger.github.io/blog/acr-tasks-image-scanning/)を読み、このアイデアはもっと知られてもいいなぁと思ったのが書いたきっかけです。Thanks Eric!

## Aqua MicroScannerとは

Aqua Security社はコンテナー関連の包括的な製品を提供していますが、MicroScannerはコンテナーイメージ含まれるパッケージの脆弱性スキャンに特化したソフトウェアで、無償で利用できます。もちろん有償版のほうが機能豊富で幅広い脅威に対応できるのですが、パッケージの脆弱性スキャンで十分という場合には、感謝してMicroScannerを使わせていただきましょう。無償/有償の機能差は[こちら](https://github.com/aquasecurity/microscanner#aqua-security-edition-comparison)を。

MicroScannerのコンセプトは、以下のリンク先にある記事やスライドがわかりやすいです。

> [Aqua’s MicroScanner: Free Image Vulnerability Scanner for Developers](https://blog.aquasec.com/microscanner-free-image-vulnerability-scanner-for-developers)

> [What's so hard about vulnerability scanning?](https://speakerdeck.com/lizrice/whats-so-hard-about-vulnerability-scanning)

> [Aqua MicroScanner - A free-to-use tool that scans container images for package vulnerabilities - GitHub](https://github.com/aquasecurity/microscanner)

## トークンの取得

MicroScannerの実行にはトークンが要ります。以下の手順で、指定したメールアドレスに送られてきます。メールを確認し、控えておきましょう。

```
$ docker run --rm -it aquasec/microscanner
```

## コンテナービルド時に実行してみる

以降、[ここ](https://github.com/ToruMakabe/aqua-sample/tree/master)にサンプルを置いておきましたので、このfork、cloneを前提に話をすすめます。

ACRでの自動実行の前に、MicroScannerをどう使うか、どんな動きをするのかを見ておきましょう。

まずはじめに、こんなコンテナーイメージを作ります。ファイルはallin.Dockerfileです。

```
FROM alpine:3.3
RUN apk add --no-cache ca-certificates
ADD https://get.aquasec.com/microscanner /
RUN chmod +x /microscanner
ARG token
RUN /microscanner ${token} && rm /microscanner
RUN echo "No vulnerabilities!"
CMD ["echo", "Hello"]
```

Apline Linuxをベースに、実行したらHelloとechoするだけのコンテナーです。ビルド時にイメージ作成環境内でMicroScannerをダウンロードし、実行します。Alpineのバージョンは3.3で、ちょっと古いものを指定しています。さあ何が起こるでしょう。

```
$ docker build . -f ./allin.Dockerfile --build-arg=token=<your token> --no-cache
Sending build context to Docker daemon  43.01kB
Step 1/8 : FROM alpine:3.3
 ---> a6fc1dbfa81a
[snip]
Step 6/8 : RUN /microscanner ${token} && rm /microscanner
 ---> Running in 5fc877fe03b3
2019-08-04 14:02:23.822 INFO    Contacting CyberCenter...       {"registry": "", "image": ""}
2019-08-04 14:02:25.090 INFO    CyberCenter connection established      {"registry": "", "image": "", "api_version": "4"}
2019-08-04 14:02:25.771 INFO    Processing results...   {"registry": "", "image": ""}
2019-08-04 14:02:27.065 INFO    Applying image assurance policies...    {"registry": "", "image": ""}
{
  "scan_started": {
    "seconds": 1564927343,
    "nanos": 722759087
  },
  "scan_duration": 2,
  "digest": "cbaf1026d5a0e866536032b2c5bae5a4ead085f61900b9e976e50030c0b7163e",
  "os": "alpine",
  "version": "3.3.3",
  "resources": [
    {
      "resource": {
        "format": "apk",
        "name": "busybox",
        "version": "1.24.2-r2",
        "arch": "x86_64",
        "cpe": "pkg:/alpine:3.3.3:busybox:1.24.2-r2",
        "license": "GPL2",
        "name_hash": "1a0be787cebd01a5ca5d163e1502c1c6"
      },
      "scanned": true,
      "vulnerabilities": [
        {
          "name": "CVE-2015-9261",
          "description": "huft_build in archival/libarchive/decompress_gunzip.c in BusyBox before 1.27.2 misuses a pointer, causing segfaults and an application crash during an unzip operation on a specially crafted ZIP file.",
          "nvd_score": 4.3,
          "nvd_score_version": "CVSS v2",
          "nvd_vectors": "AV:N/AC:M/Au:N/C:N/I:N/A:P",
          "nvd_severity": "medium",
          "nvd_url": "https://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2015-9261",
          "vendor_score": 4.3,
          "vendor_score_version": "CVSS v2",
          "vendor_vectors": "AV:N/AC:M/Au:N/C:N/I:N/A:P",
          "vendor_severity": "medium",
          "publish_date": "2018-07-26",
          "modification_date": "2019-06-13",
          "nvd_score_v3": 5.5,
          "nvd_vectors_v3": "CVSS:3.0/AV:L/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H",
          "nvd_severity_v3": "medium",
          "vendor_score_v3": 5.5,
          "vendor_vectors_v3": "CVSS:3.0/AV:L/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H",
          "vendor_severity_v3": "medium"
        },
        {
          "name": "CVE-2016-2147",
          "description": "Integer overflow in the DHCP client (udhcpc) in BusyBox before 1.25.0 allows remote attackers to cause a denial of service (crash) via a malformed RFC1035-encoded domain name, which triggers an out-of-bounds heap write.",
          "nvd_score": 5,
          "nvd_score_version": "CVSS v2",
          "nvd_vectors": "AV:N/AC:L/Au:N/C:N/I:N/A:P",
          "nvd_severity": "medium",
          "nvd_url": "https://web.nvd.nist.gov/view/vuln/detail?vulnId=CVE-2016-2147",
          "vendor_score": 5,
          "vendor_score_version": "CVSS v2",
          "vendor_vectors": "AV:N/AC:L/Au:N/C:N/I:N/A:P",
          "vendor_severity": "medium",
          "publish_date": "2017-02-09",
          "modification_date": "2019-06-13",
          "nvd_score_v3": 7.5,
          "nvd_vectors_v3": "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
          "nvd_severity_v3": "high",
          "vendor_score_v3": 7.5,
          "vendor_vectors_v3": "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H",
          "vendor_severity_v3": "high"
        },
[snip]
  "vulnerability_summary": {
    "total": 8,
    "high": 1,
    "medium": 7,
    "low": 0,
    "negligible": 0,
    "sensitive": 0,
    "malware": 0,
    "score_average": 4.9624996,
    "max_score": 7.5
  },
  "scan_options": {},
  "initiating_user": "token",
  "data_date": 1564873427,
  "changed_result": false,
  "function_metadata": {}
}
The command '/bin/sh -c /microscanner ${token} && rm /microscanner' returned a non-zero code: 4
```

スペースの都合で省きましたが、いっぱいひっかかりましたね。そして深刻度highの脆弱性が検出されたので、そこで終了しています。

では、alpineのバージョンを現時点で最新の3.10にしてみましょう。

```
$ docker build . -f ./allin.Dockerfile --build-arg=token=<your token> --no-cache
Sending build context to Docker daemon  43.01kB
Step 1/8 : FROM alpine:3.10
 ---> b7b28af77ffe
[snip]
Step 6/8 : RUN /microscanner ${token} && rm /microscanner
 ---> Running in ed5ee7337de6
[snip]
  "vulnerability_summary": {
    "total": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "negligible": 0,
    "sensitive": 0,
    "malware": 0
  },
  "scan_options": {},
  "initiating_user": "token",
  "data_date": 1564873427,
  "changed_result": false,
  "function_metadata": {}
}
Removing intermediate container ed5ee7337de6
 ---> e76950bc83eb
Step 7/8 : RUN echo "No vulnerabilities!"
 ---> Running in 1afef0fa5ace
No vulnerabilities!
Removing intermediate container 1afef0fa5ace
 ---> b36bd76dd37b
Step 8/8 : CMD ["echo", "Hello"]
 ---> Running in 33b0f554bb3f
Removing intermediate container 33b0f554bb3f
 ---> a4f61c940dce
Successfully built a4f61c940dce
```

脆弱性は検出されず、ビルドが正常終了しました。これがMicroScannerの基本的な動きです。ちなみに--continue-on-failureオプションで、脆弱性highのブツが見つかっても処理を継続することはできます。

## ACR Tasksでのビルドに組み込む

ではACR Tasksに組み込みましょう。ポイントはMicroScannerに渡すトークンをいかに秘匿し、ACR Tasksに渡すかです。GitHubとかでご開帳しないように気を付けましょう。

* Key Vaultにトークンを保管
* Managed IdentityへKey Vaultシークレットの読み取り権限を付与
* ACR TasksへManaged Identityを実行時に割り当て

この方針とします。これであればトークンをDockerfileやタスク定義ファイルに書く必要がなく、ご開帳のリスクを減らせます。

リソースグループ、Key Vaultとシークレットを作成します。

```
$ az group create -n rg-aqua-sample -l japaneast
$ az keyvault create -g rg-aqua-sample -n your-aqua-sample
$ az keyvault secret set --vault-name your-aqua-sample -n aqua-key --value "<your token>"
```

ユーザー割り当てManaged Identityを作り、IDを取得して変数へ入れておきます。

```
$ az identity create -g rg-aqua-sample -n aqua-identity
$ resourceID=$(az identity show -g rg-aqua-sample -n aqua-identity --query id -o tsv)
$ principalID=$(az identity show -g rg-aqua-sample -n aqua-identity --query principalId -o tsv)
```

Key Vaultシークレットの読み取り権限を、先ほど作ったManaged Identityに付与します。

```
$ az keyvault set-policy -g rg-aqua-sample -n your-aqua-sample --object-id $principalID --secret-permissions get
```

これで準備はOKです。次はACR Tasksでのビルド定義をします。

まずはDockerfileです。先ほどはビルド時にコンテナー作成環境内でMicroScannerを実行しましたが、ACR Tasksはマルチステップ定義ができるので、コンテナーイメージのビルドとスキャンをステップ分離します。なのでDockerfileはシンプルです。脆弱性検出時の動きを見たいので、Alpineのバージョンは3.3としました。

```
FROM alpine:3.3
RUN apk add --no-cache ca-certificates
CMD ["echo", "Hello"]
```

そしてACR Tasksのタスク定義をします。ファイルはaqua-scan.yamlです。コンテナーイメージビルドのステップと、脆弱性スキャンのステップを分離しています。脆弱性スキャンのステップが失敗したらそこでタスクは終了し、レジストリへpushしません。

```
version: v1.0.0

secrets:
  - id: key
    keyvault: https://your-aqua-sample.vault.azure.net/secrets/aqua-key

steps:
  - build: . -t {{.Run.Registry}}/alpine-hello:{{.Run.ID}}

  # Create a new Dockerfile with the scanner added to the previous image.
  - cmd: |
      bash -c 'echo "FROM {{.Run.Registry}}/alpine-hello:{{.Run.ID}}
      ADD https://get.aquasec.com/microscanner /
      RUN chmod +x /microscanner
      RUN /microscanner {{.Secrets.key}}" > scan.Dockerfile'

  # Scan the image using the Dockerfile I created.
  - build: . -f scan.Dockerfile -t scanned

  # Only push the image if the scan was successful.
  - push: ["{{.Run.Registry}}/alpine-hello:{{.Run.ID}}"]
```

MicroScannerのトークンをKey Vaultシークレットから渡していますね。それではタスクを作成してみましょう。

```
$ az acr task create -r your-acr -n aqua-scan -c https://github.com/your-repo/aqua-sample.git -f aqua-scan.yaml --commit-trigger-enabled false --pull-request-trigger-enabled false --assign-identity $resourceID
```

タスクを実行します。

```
$ az acr task run -r your-acr -n aqua-scan                                                                           
Queued a run with ID: ce9                                                                                               
Waiting for an agent...                                                                                                 
2019/08/05 05:20:21 Downloading source code...
2019/08/05 05:20:26 Finished downloading source code
2019/08/05 05:20:26 Using acb_vol_b9db0e18-786e-46bc-8b96-831ec44fd8ea as the home volume
2019/08/05 05:20:28 Creating Docker network: acb_default_network, driver: 'bridge'
2019/08/05 05:20:29 Successfully set up Docker network: acb_default_network
2019/08/05 05:20:29 Setting up Docker configuration...
2019/08/05 05:20:30 Successfully set up Docker configuration
2019/08/05 05:20:30 Logging in to registry: your-acr.azurecr.io
2019/08/05 05:20:31 Successfully logged into your-acr.azurecr.io
2019/08/05 05:20:31 Executing step ID: acb_step_0. Timeout(sec): 600, Working directory: '', Network: 'acb_default_network'
2019/08/05 05:20:31 Scanning for dependencies...
2019/08/05 05:20:31 Successfully scanned dependencies
2019/08/05 05:20:31 Launching container with name: acb_step_0
[snip]
2019/08/05 05:20:40 Successfully executed container: acb_step_0
2019/08/05 05:20:40 Executing step ID: acb_step_1. Timeout(sec): 600, Working directory: '', Network: 'acb_default_network'
2019/08/05 05:20:40 Launching container with name: acb_step_1
2019/08/05 05:20:41 Successfully executed container: acb_step_1
2019/08/05 05:20:41 Executing step ID: acb_step_2. Timeout(sec): 600, Working directory: '', Network: 'acb_default_network'
2019/08/05 05:20:41 Scanning for dependencies...
2019/08/05 05:20:42 Successfully scanned dependencies
2019/08/05 05:20:42 Launching container with name: acb_step_2
Sending build context to Docker daemon  70.66kB
Step 1/4 : FROM your-acr.azurecr.io/alpine-hello:ce9
 ---> 4a636059f6cd
Step 2/4 : ADD https://get.aquasec.com/microscanner /

 ---> 0a868f54d9ff
Step 3/4 : RUN chmod +x /microscanner
 ---> Running in ef6f0e640feb
Removing intermediate container ef6f0e640feb
 ---> 289d9803ee00
Step 4/4 : RUN /microscanner your-token
 ---> Running in 52c234f73757
2019-08-05 05:20:51.051 INFO    Contacting CyberCenter...       {"registry": "", "image": ""}                           2019-08-05 05:20:52.259 INFO    CyberCenter connection established      {"registry": "", "image": "", "api_version": "4"}
2019-08-05 05:20:52.929 INFO    Processing results...   {"registry": "", "image": ""}                                   2019-08-05 05:20:54.308 INFO    Applying image assurance policies...    {"registry": "", "image": ""}                   {
  "scan_started": {
    "seconds": 1564982450,
    "nanos": 892464816
  },
[snip]
  "vulnerability_summary": {
    "total": 8,
    "high": 1,
    "medium": 7,
    "low": 0,
    "negligible": 0,
    "sensitive": 0,
    "malware": 0,
    "score_average": 4.9624996,
    "max_score": 7.5
  },
  "scan_options": {},
  "initiating_user": "token",
  "data_date": 1564959825,
  "changed_result": false,
  "function_metadata": {}
}
The command '/bin/sh -c /microscanner your-token' returned a non-zero code: 4
2019/08/05 05:20:54 Container failed during run: acb_step_2. No retries remaining.
failed to run step ID: acb_step_2: exit status 4

Run ID: ce9 failed after 34s. Error: failed during run, err: exit status 1
```

コンテナーイメージに脆弱性のあるパッケージが含まれているため、レジストリへpushをせずに終了しました。ではDockerfileのベースイメージバージョンをAlpine 3.10に変えてタスクを再実行してみます。

```
$ az acr task run -r your-acr -n aqua-scan
Queued a run with ID: cea                                                                                               
Waiting for an agent...                                                                                                 
2019/08/05 05:22:25 Downloading source code...
[snip]
2019/08/05 05:23:02 Step ID: acb_step_3 marked as successful (elapsed time in seconds: 2.449787)
2019/08/05 05:23:02 The following dependencies were found:
2019/08/05 05:23:02
- image:
    registry: your-acr.azurecr.io
    repository: alpine-hello
    tag: cea
    digest: sha256:56fbc474e76d215d92126f8bd56d7a3a91affd35d254cef5649f80fc337f1fb2
  runtime-dependency:
    registry: registry.hub.docker.com
    repository: library/alpine
    tag: "3.10"
    digest: sha256:6a92cd1fcdc8d8cdec60f33dda4db2cb1fcdcacf3410a8e05b3741f44a9b5998
  git:
    git-head-revision: b88031f5eb47acfe4ed83f8beda3758f8441d2e8
- image:
    registry: registry.hub.docker.com
    repository: library/scanned
    tag: latest
  runtime-dependency:
    registry: your-acr.azurecr.io
    repository: alpine-hello
    tag: cea
    digest: sha256:56fbc474e76d215d92126f8bd56d7a3a91affd35d254cef5649f80fc337f1fb2
  git:
    git-head-revision: b88031f5eb47acfe4ed83f8beda3758f8441d2e8


Run ID: cea was successful after 38s
```

pushできました。
