+++
Categories = ["Kubernetes"]
Tags = ["Kubernetes", "Azure"]
date = "2019-06-17T22:00:00+09:00"
title = "Azure Kubernetes Serviceでシークレットを管理する6つの方法"

+++

## 何の話か

Kubernetesでアプリケーションが使うシークレットを扱うには、いくつかのやり方があります。地味ですが重要な要素なので、整理しましょう。この記事では主にDB接続文字列やAPIキーなど、アプリケーションが必要とする、限られた人のみが扱うべき情報を「シークレット」とします。

それぞれの仕組みには踏み込まず、どんな課題を解決するか、どのように使えるか、その効果を中心に書きます。それでもちょっと長いですがご容赦ください。

Azure Kubernetes Serviceを題材にしますが、他のKubernetes環境でも参考になると思います。

## 6つの方法

以下の6つの方法を順に説明します。

1. アプリケーションに書く
2. マニフェストに書く
3. KubernetesのSecretにする
4. Key Vaultで管理し、その認証情報をKubernetesのSecretにする
5. Key Vaultで管理し、Podにそのアクセス権を付与する (Pod Identity)
6. Key Vaultで管理し、Podにボリュームとしてマウントする (FlexVolume)

## アプリケーションに書く

いわゆるハードコーディングです。論外、としたいところですが、何が問題なのかざっと確認しておきましょう。代表的な問題点は、次の2つです。

* アプリケーションのソースコードにアクセスできるすべての人がシークレットを知り得る
* シークレットの変更時、影響するすべてのソースを変更し再ビルドが必要

シークレットが平文で書かれたソースコードリポジトリをパブリックに御開帳、という分かりやすい事案だけがリスクではありません。プライベートリポジトリを使っていても、人の出入りがあるチームでの開発運用、シークレット漏洩時の変更やローテーションなどの運用を考えると、ハードコーディングは取りづらい選択肢です。

よって以降で紹介する方法は、アプリケーションにシークレットをハードコーディングせず、何かしらの手段で外部から渡します。

## マニフェストに書く

Kubernetesではアプリケーションの実行時に、環境変数を渡すことができます。

```
apiVersion: apps/v1
kind: Deployment
[snip]
    spec:
      containers:
      - name: getsecret
        image: torumakabe/getsecret:from-env
        env:
        - name: SECRET_JOKE
          value: "Selfish sell fish."
```

これはコンテナーの実行(Deployment作成)時に、環境変数 SECRET_JOKE を渡すマニフェストの例です。ジョークも人によっては立派なシークレットです。値(value)はマニフェストに直書きしています。

この環境変数をアプリケーションで読み込みます。Goでジョークを披露するWebアプリを書くと、こんな感じです。

```
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
)

func getSecret(w http.ResponseWriter, r *http.Request) {
	secret := os.Getenv("SECRET_JOKE")

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", secret))
}

func main() {
	http.HandleFunc("/", getSecret)
	http.ListenAndServe(":8080", nil)
}
```

Goの場合は os.Getenv で環境変数を取得します。これで、とっておきのジョークを、チームメンバーにデプロイ時まで知られることなくアプリを開発できます。また、ジョークの反応がいまいちだった場合や、飽きられた場合はマニフェストを変更して再デプロイすれば済みます。アプリケーションを変更、再ビルドする必要はありません。

ですが、マニフェストもアプリケーションのソースコードと同様に共有するでしょうから、直書きされたシークレットがチームメンバーの目に触れる可能性は、あります。

マニフェストを置くリポジトリのアクセス制御は、マニフェストを誰が作り、デプロイするかによります。深いテーマなので踏み込みませんが、少なくともマニフェストにシークレットの値を平文で書くなら、マニフェストにアクセスできる人を限定すべきでしょう。これは開発、運用の大きな制約条件になり得ます。

なお、シークレットだけを暗号化してソースコードを管理し、デプロイ時に復号化する、という方法もあります。Helmのラッパーで、Helmの実行時に暗号化されたシークレットファイルを復号化する[helm-secrets](https://github.com/futuresimple/helm-secrets)がその例です。[SOPS](https://github.com/mozilla/sops)を活用しています。

ただしKubernetesには復号化されて単なる環境変数として送られますので、Podの参照権限があれば値は読めてしまいます。

```
$ kubectl get po getsecret-hoge -o yaml
[snip]
spec:
  containers:
  - env:
    - name: SECRET_JOKE
      value: Selfish sell fish.
```

なので次からは、マニフェストに直接書かずに済む方法を紹介します。

## KubernetesのSecretにする

KubernetesのリソースにSecretという、ズバリな名前のリソースがあります。Secretは平文ではなくBase64で符号化のうえ、etcd内に保管されます。そしてKubernetesとetcdのバージョンと設定によっては、etcdは暗号化できます。AKSのetcdは ["AKS does encrypt secrets-at-rest" つまり暗号化されています](https://github.com/Azure/kubernetes-kms)。

Secretはそれを受け取るPodの実行サーバー上では永続化されず、tmpfs(揮発ファイルシステム)に書き込まれます。

Secretは以下のようなマニフェストで作成します。

```
apiVersion: v1
kind: Secret
metadata:
  name: joke
type: Opaque
data:
  joke: U2VsZmlzaCBzZWxsIGZpc2gu
```

値はBase64符号化した結果を書きます。当然ながらBase64デコードできるので、マニフェストの管理はご注意を。

このSecretをアプリケーションに環境変数として渡すマニフェストの書き方は、先ほどの環境変数を直接書く方法とあまり変わりません。envのvalueFrom以下でSecretを指定します。

```
apiVersion: apps/v1
kind: Deployment
[snip]
    spec:
      containers:
      - name: getsecret
        image: torumakabe/getsecret:from-env
        env:
        - name: SECRET_JOKE
          valueFrom:
            secretKeyRef:
              name: joke
              key: joke
```

これでOKです。アプリケーションは環境変数を読むのに変わりがないため、そのままで構いません。なお、Secretは符号化されていますが、アプリケーションはデコードされた結果を受け取ります。

もちろんPodの参照権限だけでは、中身をKubernetes API経由で見ることはできません。

```
$ kubectl get po getsecret-fuga -o yaml
[snip]
spec:
  containers:
  - env:
    - name: SECRET_JOKE
      valueFrom:
        secretKeyRef:
          key: joke
          name: joke
```

また、マニフェストに値を書かないため、シークレットの変更時、影響を受けるマニフェストを変更する必要がないのもメリットです。Secretを更新して[Podをリスタート](https://qiita.com/sonots/items/8ddda98ffed3763d96fe)すれば済みます。

さて、これでかなり楽になったのですが、まだ改善の余地があります。こんな悩みが残ります。

* シークレットの管理者がKubernetesの管理者とは別で、Kubernetesの操作権限を渡したくない
  * 接続するDBがKuberentes外部にあり、管理者が別、なんてことはよくある
* etcdが暗号化されているとはいえ、シークレットは明示的に、特化型のサービスでコントロールしたい
* etcdに入れる前のマニフェストやソース管理、符号化作業が不安

そこで、以降はAzureのシークレット管理サービスであるKey Vaultを活用した方法を解説します。

## Key Vaultで管理し、その認証情報をKubernetesのSecretにする

Key VaultはシークレットをHSMで保護し、かつきめ細かいアクセスポリシー制御ができる、シークレット管理に特化したサービスです。暗号化キーや証明書の管理もできます。ここへKuberentesで動くアプリケーションのシークレットを入れてみましょう。

まずはアプリケーションのサンプルです。先ほどのGoで書いたWebアプリを、Azure SDK for Goを使って、Key Vaultからシークレットが読めるように書き換えます。

```
package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/Azure/azure-sdk-for-go/services/keyvault/auth"
	"github.com/Azure/azure-sdk-for-go/services/keyvault/2016-10-01/keyvault"
)

func getKeyvaultSecret(w http.ResponseWriter, r *http.Request) {
	authorizer, err := auth.NewAuthorizerFromEnvironment()
	if err != nil {
		log.Printf("unable to get your authorizer object: %v", err)
		return
	}

	keyClient := keyvault.New()
	keyClient.Authorizer = authorizer

	keyvaultName := os.Getenv("AZURE_KEYVAULT_NAME")
	keyvaultSecretName := os.Getenv("AZURE_KEYVAULT_SECRET_NAME")
	keyvaultSecretVersion := os.Getenv("AZURE_KEYVAULT_SECRET_VERSION")

	secret, err := keyClient.GetSecret(context.Background(), fmt.Sprintf("https://%s.vault.azure.net", keyvaultName), keyvaultSecretName, keyvaultSecretVersion)
	if err != nil {
		log.Printf("unable to get your Keyvault secret: %v", err)
		return
	}

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", *secret.Value))
}

func main() {
	http.HandleFunc("/", getKeyvaultSecret)
	http.ListenAndServe(":8080", nil)
}
```

ポイントは2つです。

### Key Vaultを読めるように認証する

[auth.NewAuthorizerFromEnvironment()](https://github.com/Azure/azure-sdk-for-go/blob/master/services/keyvault/auth/auth.go) は環境変数を確認し、以下の順番で認証を試みます。

* クライアント資格情報(サービスプリンシパル)
* X509 証明書
* ユーザー名/パスワード
* Azure Managed Identiy

確認される環境変数名など、詳細は[公式ドキュメント](https://docs.microsoft.com/ja-jp/go/azure/azure-sdk-go-authorization#use-environment-based-authentication)でご確認を。

このサンプルは、クライアント資格情報、つまりサービスプリンシパルを使ってKey Vaultの認証を行います。環境変数 AZURE_TENANT_ID、AZURE_CLIENT_ID、AZURE_CLIENT_SECRET が設定された環境で auth.NewAuthorizerFromEnvironment() を呼ぶと、クライアント資格情報を使った認証が選択されます。

### Key Vault名、シークレット名、バージョン名を環境変数で渡す

これは見ての通りですね。シークレットが格納されているKey Vaultを指定するため、 AZURE_KEYVAULT_NAME などを環境変数から読み込みます。

他の言語でどう書くかは、それぞれSDKのドキュメントを参考にしてください。

では、マニフェストを見てみましょう。

```
apiVersion: apps/v1
kind: Deployment
[snip]
    spec:
      containers:
      - name: getsecret
        image: torumakabe/getsecret:keyvault
        env:
        - name: AZURE_KEYVAULT_NAME
          value: your-keyvault-name
        - name: AZURE_KEYVAULT_SECRET_NAME
          value: joke
#       - name: AZURE_KEYVAULT_SECRET_VERSION
#         value: your-keyvault-secret-version  #[OPTIONAL] will get latest if commented out
        - name: AZURE_TENANT_ID
          valueFrom:
            secretKeyRef:
              name: joke-sp
              key: tenantId
        - name: AZURE_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: joke-sp
              key: clientId
        - name: AZURE_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: joke-sp
              key: clientSecret
```

クライアント資格情報であるサービスプリンシパルは直接書かず、KubernetesのSecretにして環境変数に渡しましょう。なお、サービスプリンシパルには対象のKey Vaultを参照(Get)のみできるKey Vaultポリシーを設定し、かつRBACもスコープを対象のKey Veultに限定したReaderにしておくと、リスクを限定できます。

これでKey Vaultのjokeというシークレットにジョークを入れておけば、読み込めます。

さて、Key Vaultにシークレットを入れてグッと堅くなったわけですが、もう少し追求してみましょう。そう、サービスプリンシパルのクライアントIDとクライアントシークレットをSecretに入れる面倒さが残っています。ここを無くせないものか。

## Key Vaultで管理し、Podにそのアクセス権を付与する (Pod Identity)

先ほどGoの auth.NewAuthorizerFromEnvironment() の認証順を紹介した際に [Azure Managed Identiy](https://docs.microsoft.com/ja-jp/azure/active-directory/managed-identities-azure-resources/overview) を使えることが分かりました。Managed Identityは、仮想マシンなどアプリケーションの動く環境へ事前に資格を付与し、アプリケーションは資格情報を持たずに済む仕組みです。もしManaged IdentiyをPodから使えれば、アプリケーションやマニフェストへ資格情報を書く必要はありません。それを実現するのが、Pod Identityです。

まず概念を理解するため、ざっと公式ドキュメントを読むことをお勧めします。

> [Azure Kubernetes Service (AKS) でのポッドのセキュリティに関するベスト プラクティス - 資格情報の公開を制限する](https://docs.microsoft.com/ja-jp/azure/aks/developer-best-practices-pod-security#limit-credential-exposure)

でも、これだけだとピンとこないと思います。導入して何が嬉しいかを理解してから、再度読んでみて下さい。理解が深まると思います。

Pod Identitiyを導入した環境では、マニフェストはこうなります。

```
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: getsecret
    aadpodidbinding: joke
[snip]
  template:
    metadata:
      labels:
        app: getsecret
        aadpodidbinding: joke
[snip]
    spec:
      containers:
      - name: getsecret
        image: torumakabe/getsecret:keyvault
        env:
        - name: AZURE_KEYVAULT_NAME
          value: your-keyvault-name
        - name: AZURE_KEYVAULT_SECRET_NAME
          value: joke
#       - name: AZURE_KEYVAULT_SECRET_VERSION
#         value: your-keyvault-secret-version  #[OPTIONAL] will get latest if commented out
```

識別子 aadpodidbinding を指定する必要はありますが、Key Vaultの資格情報をマニフェストへ書く必要がありません。素晴らしい。Goの auth.NewAuthorizerFromEnvironment() は他の認証に使われる環境変数が全てセットされていない時、Managed Identity認証を選択します。そしてPod Identityの基盤であるNMIを通じ、Azure ADから認証トークンを得るわけです。

なお、このPod Identitiyはオープンソースプロジェクトとして開発されています。試してみたい、詳細な実装を知りたい人はこちらを。

> [AAD Pod Identity](https://github.com/azure/aad-pod-identity)

Pod IdentitiyはAKSとの統合を目的に開発されており、公式サイトでも[状況が公開されています](https://azure.microsoft.com/ja-jp/updates/aks-pod-identity/)。オープンに開発してニーズを募り、実績を積んでいる状況であるため、GitHub上でベストエフォートなサポートが行われています。

さて、ここで終わりでしょうか。いえ、まだ改善の余地があります。

## Key Vaultで管理し、Podにボリュームとしてマウントする (FlexVolume)

理想では、アプリケーションはプラットフォームをあまり意識せずに書きたいものです。プラットフォームそのものを書く、繋ぐコードであれば仕方ないですが、そうでなければアプリケーションは汎用的に書きたいですよね。ですが、これまでKey Vaultからシークレットを読むアプリケーションのサンプルでは、Azure SDK for Goを使って、Key Vault固有の処理を書いていました。

それを書かずに済む方法があります。FlexVolumeです。実は先に紹介したPod Identiyのドキュメントで、次に説明されていました。

> [Azure Kubernetes Service (AKS) でのポッドのセキュリティに関するベスト プラクティス - 資格情報の公開を制限する](https://docs.microsoft.com/ja-jp/azure/aks/developer-best-practices-pod-security#limit-credential-exposure)

これも使い方から理解したほうがいいでしょう。FlexVolumeはKey Vaultのシークレット、暗号化キー、証明書をPodへVolumeとしてマウントできる仕組みです。つまりアプリケーションがシークレットを、あたかもファイルシステム上のファイルであるかのように読むことができます。

これまでのサンプルアプリケーションを、こう変えられます。

```
package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
)

func getSecret(w http.ResponseWriter, r *http.Request) {
	secret, err := ioutil.ReadFile("/kvmnt/joke")
	if err != nil {
		log.Printf("unable to read your secret file: %v", err)
		return
	}

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", string(secret)))
}

func main() {
	http.HandleFunc("/", getSecret)
	http.ListenAndServe(":8080", nil)
}
```

シークレットはKey Vaultにあるのですが、アプリ的にはファイルを読んでるだけです。ではマニフェストはどうでしょう。

```
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: getsecret
    aadpodidbinding: joke
[snip]
  template:
    metadata:
      labels:
        app: getsecret
        aadpodidbinding: joke
[snip]
    spec:
      containers:
      - name: getsecret
        image: torumakabe/getsecret:flexvol
        volumeMounts:
        - name: joke
          mountPath: /kvmnt
          readOnly: true
      volumes:
      - name: joke
        flexVolume:
          driver: "azure/kv"
          options: 
            usepodidentity: "true"
            keyvaultname: "your-keyvault-name"
            keyvaultobjectnames: joke
            keyvaultobjecttypes: secret
            keyvaultobjectversions: ""  #[OPTIONAL] will get latest if empty
            resourcegroup: "your-keyvault-rg"
            subscriptionid: "your-subscription-id"
            tenantid: "your-tenant-id"
```

Key VaultをVolumeとしてマウントしていることが、分かるでしょうか。もちろん資格情報を書く必要はありません。

Flex VolumeはPod Identitiyと同様にオープンソースプロジェクトとして開発されています。試してみたい場合は、こちらを。

> [Kubernetes-KeyVault-FlexVolume](https://github.com/Azure/kubernetes-keyvault-flexvol)

ちなみにHashiCorpのVaultも、似たようなコンセプトです。

> [Vault Agent with Kubernetes](https://learn.hashicorp.com/vault/identity-access-management/vault-agent-k8s)

## まとめ

ちょっと長くなりましたが、現状Azure Kuberentes Serviceで使えるシークレット管理手法を整理しました。洗練された方法がベストとも限りません。洗練された仕組みを理解できていない状態で使うより、シンプルなやり方を選んだ方がリスクを減らせるかもしれません。組織と役割、セキュリティポリシー、技術的難易度、オープンソースプロジェクトへのスタンスなど、置かれた環境によって評価はそれぞれでしょう。

唯一の解はありませんが、みなさまの検討の参考になれば幸せです。
