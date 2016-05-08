+++
Categories = ["Azure"]
Tags = ["Azure", "Functions", "Facebook", "Bot"]
date = "2016-05-08T14:00:00+09:00"
title = "Azure FunctionsとFacebook Messenger APIで好みなんて聞いてないBotを作る"

+++

## まだ好みなんて聞いてないぜ
Build 2016で、[Azure Functions](https://azure.microsoft.com/ja-jp/services/functions/)が発表されました。

Azure Functionsは、

1. アプリを放り込めば動く。サーバの管理が要らない。サーバレス。  #でもこれは従来のPaaSもそう
2. 利用メモリ単位での、粒度の細かい課金。  #現在プレビュー中にて、詳細は今後発表
3. Azure内外機能との、容易なイベント連動。

が特徴です。AWSのLambdaと似てるっちゃ似ています。

何が新しいかというと、特に3つ目の特徴、イベント連動です。触ってみなければわからん、ということで、流行りのBotでも作ってみたいと思います。

### 基本方針

* FunctionsはAzure内の様々な機能と[イベント連動](https://azure.microsoft.com/ja-jp/documentation/articles/functions-reference/#bindings)できるが、あえてサンプルの少ないAzure外とつないでみる
* Facebook Messenger APIを使って、webhook連動する
* Facebook Messenger向けに書き込みがあると、ランダムでビールの種類と参考URLを返す
* ビールは[Craft Beer Association](http://beertaster.org/beerstyle/web/beerstyle_main_j.html)の分類に従い、協会のビアスタイル・ガイドライン参考ページの該当URLを返す
* Botらしく、それらしい文末表現をランダムで返す
* 好みとか文脈は全く聞かないぜSorry
* アプリはNodeで書く。C#のサンプルは増えてきたので
* 静的データをランダムに返す、かつ少量なのでメモリ上に広げてもいいが、せっかくなのでNodeと相性のいいDocumentDBを使う
* DocumentDBではSQLでいうORDER BY RAND()のようなランダムな問い合わせを書けないため、ストアドプロシージャで実装する  #[サンプル](https://gist.github.com/murdockcrc/12266f9d844be416a6a0)
* FunctionsとGithubを連携し、GithubへのPush -> Functionsへのデプロイというフローを作る

ひとまずFunctionsとBotの枠組みの理解をゴールとします。ロジックをたくさん書けばそれなりに文脈を意識した返事はできるのですが、書かずに済む仕組みがこれからいろいろ出てきそうなので、書いたら負けの精神でぐっと堪えます。

## 必要な作業

以下が必要な作業の流れです。

* Azureで
    * Function Appの作成  #順番1
    * Bot用Functionの作成 #順番2
    * Facebook Messenger APIとの接続検証  #順番6
    * Facebook Messenger API接続用Tokenの設定  #順番8
    * DocumentDBのデータベース、コレクション作成、ドキュメント投入  #順番9
    * DocumentDBのストアドプロシージャ作成  #順番10
    * Function Appを書く  #順番11
    * FunctionsのサイトにDocumentDB Node SDKを導入 #順番12
    * Function AppのGithub連携設定  #順番13
    * Function Appのデプロイ (GithubへのPush)  #順番14
* Facebookで
    * Facebook for Developersへの登録  #順番3
    * Botをひも付けるFacebook Pageの作成  #順番4
    * Bot用マイアプリの作成  #順番5
    * Azure Functionsからのcallback URLを登録、接続検証  #順番6
    * Azure Functions向けTokenを生成 #順番7

アプリのコード書きの他はそれほど重くない作業ですが、すべての手順を書くと本ができそうです。Function Appの作りにポイントを絞りたいので、以下、参考になるサイトをご紹介します。

* Function Appを書くまで、順番1〜2、5〜8は、[こちらのブログエントリ](http://oauth.jp/blog/2016/04/19/fb-message-callback-with-azure-function/)がとても参考になります。
* Facebook for Developersへの登録、順番3は、https://developers.facebook.com/ から。いきなり迷子の人は、[こちら](http://qiita.com/k_kuni/items/3d7176ee4e3009b45dd8)も参考に。
* Facebook Pageの作成は、[ここ](http://allabout.co.jp/gm/gc/387840/)を。Botで楽しむだけなら細かい設定は後回しでいいです。
* DocumentDBについては、[公式](https://azure.microsoft.com/ja-jp/documentation/articles/documentdb-introduction/)を。
     * [DBアカウント〜コレクション作成](https://azure.microsoft.com/ja-jp/documentation/articles/documentdb-create-account/)
     * [ドキュメントインポート](https://azure.microsoft.com/ja-jp/documentation/articles/documentdb-import-data/)
     * [ストアドプロシージャ](https://azure.microsoft.com/ja-jp/documentation/articles/documentdb-programming/)
* FunctionsのサイトにDocumentDB Node SDKを導入する順番12は、[こちら](http://tech.guitarrapc.com/entry/2016/04/05/043723)を。コンソールからnpm installできます。     
* Github連携設定、順番13〜14は、[こちら](http://tech.guitarrapc.com/entry/2016/04/03/051552)がとても参考になります。

## Function Appのサンプル

Githubにソースを[置いておきます](https://github.com/ToruMakabe/MakabeerBot)。

ちなみにこのディレクトリ階層はGithub連携を考慮し、Function Appサイトのそれと合わせています。以下がデプロイ後のサイト階層です。

```
D:\home\site\wwwroot
├── fb-message-callback
│   ├── TestOutput.json
│   ├── function.json
│   └── index.js  #これが今回のアプリ
├── node_modules  #DocumentDB Node SDKが入っている
├── host.json
├── README.md
```

ではFunction Appの実体、index.jsを見てみましょう。

```
var https = require('https');
var documentClient = require("documentdb").DocumentClient;
const databaseUrl = "dbs/" + process.env.APPSETTING_DOCDB_DB_ID;

var client = new documentClient(process.env.APPSETTING_DOCDB_ENDPOINT, { "masterKey": process.env.APPSETTING_DOCDB_AUTHKEY });

function sendTextMessage(sender, text, context) {
  getDataFromDocDB().then(function (value) {
    var msgAll = value[0].randomDocument.beer + " " + value[1].randomDocument.msg;
    var postData = JSON.stringify({
      recipient: sender,
      message: {
        "attachment":{
          "type":"template",
          "payload":{
            "template_type":"button",
            "text":msgAll,
            "buttons":[
              {
                "type":"web_url",
                "url":value[0].randomDocument.url,
                "title":"詳しく"
              }
            ]
          }
        }
      }
    });
    var req = https.request({
      hostname: 'graph.facebook.com',
      port: 443,
      path: '/v2.6/me/messages',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + process.env.APPSETTING_FB_PAGE_TOKEN
      }
    });
    req.write(postData);
    req.end();
  }).catch(function(err){
    context.log(err);
  });  
}

function getRandomDoc(sprocUrl){
  return new Promise(function (resolve, reject) {
    const sprocParams = {};
    client.executeStoredProcedure(sprocUrl, sprocParams, function(err, result, responseHeaders) {
      if (err) {
        reject(err);
      }
      if (result) {
        resolve(result);
      }
    });
  });
}

var results = {
  beer: function getBeer() {
    var collectionUrl = databaseUrl + "/colls/beer";
    var sprocUrl = collectionUrl + "/sprocs/GetRandomDoc";
    return getRandomDoc(sprocUrl).then(function (result) {
      return result;
    });
  },
  eom: function getEom() {
    var collectionUrl = databaseUrl + "/colls/eom";
    var sprocUrl = collectionUrl + "/sprocs/GetRandomDoc";
    return getRandomDoc(sprocUrl).then(function (result) {
      return result;
    });
  }
}

function getDataFromDocDB() {
  return Promise.all([results.beer(), results.eom()]);
}

module.exports = function (context, req) {
  messaging_evts = req.body.entry[0].messaging;
  for (i = 0; i < messaging_evts.length; i++) {
    evt = req.body.entry[0].messaging[i];
    sender = evt.sender;
    if (evt.message && evt.message.text, context) {
      sendTextMessage(sender, evt.message.text, context);
    }
  }
  context.done();
};
```

* 最下部のmodule.export以降のブロックで、webhookイベントを受け取ります
* それがmessageイベントで、テキストが入っていれば、sendTextMessage関数を呼びます
    * 好みは聞いてないので、以降、受け取ったテキストが読まれることはありませんが
* sendTextMessage関数内、getDataFromDocDB関数呼び出しでDocumentDBへ問い合わせてビールと文末表現をランダムに取り出します
    * コレクション"beer"、"eom(end of message)"の構造はそれぞれこんな感じ
    
```
{
  "url": "http://beertaster.org/beerstyle/web/001A.html#japanese",
  "beer": "酵母なし、ライトアメリカン・ウィートビール",
  "id": "bf3636c5-4284-4e7a-b587-9002a771f214"
}
```

```
{
  "msg": "はウマい",
  "id": "acd63222-2138-4e19-894e-dc85a950be64"
}
```

* DocumentDBの2つのコレクションへの問い合わせが終わった後、Facebookへメッセージを返すため、逐次処理目的でJavaScriptの[Promise](http://azu.github.io/promises-book/)を使っています


いかがでしょう。好みを聞かない気まぐれBotとはいえ、気軽に作れることが伝わったかと思います。

*なお、Botの外部公開には審査が必要とのことです*
