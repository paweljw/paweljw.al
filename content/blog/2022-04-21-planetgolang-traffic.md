---
date: "2022-04-21T00:00:00+02:00"
title: "Analyzing Planet Golang traffic with Julia"
coverImage: /media/planetgolang-traffic.jpg
tags:
  - julia
  - data science
comments: true
draft: false
twitterTitle: "Analyzing Planet Golang traffic with Julia"
---

As you might know, I'm running [planetgolang.dev](https://planetgolang.dev) - an unopinionated Go news aggregator. Now it's been out for a while, I want to see some stats to check if it's useful to people!

<!--more-->

It would stand to reason to do it in Go - after all, it's a Go site - but lately I've been figuring out my way around Julia. Since I intend to use Julia mostly in data science contexts, this feels like a good fit for some learning!

The site is static, distributed with AWS CloudFront. I've set it to collect logs in an S3 bucket and just... left it there. Hey, I never promised I'm the most organized person in the world. Anyway, these logs will need some lovin' before we can use them.

The AWS format is a bit weird. It's kinda-sorta-TSV, but each file begins with a preamble like this:

```
#Version: 1.0
#Fields: date time x-edge-location sc-bytes c-ip cs-method cs(Host) cs-uri-stem sc-status cs(Referer) cs(User-Agent) cs-uri-query cs(Cookie) x-edge-result-type x-edge-request-id x-host-header cs-protocol cs-bytes time-taken x-forwarded-for ssl-protocol ssl-cipher x-edge-response-result-type cs-protocol-version fle-status fle-encrypted-fields c-port time-to-first-byte x-edge-detailed-result-type sc-content-type sc-content-len sc-range-start sc-range-end
```

Only after that do the actual TSV values start. Another issue is that since August last year, it generated _a few_ files:

```
$ ls logs | wc -l
20664
```

So let's concatenate them into one megafile first, then stuff all that into a Data Frame, and then have some fun with it!

First let's write our megafile. It'll hang out in `logs/concatenated.csv`. I figured out I want quoted _after_ having gone all search-and-replace on a header row, so we'll just quote that live as well. Not great, but it's not like I'm putting these scribbles in production somewhere. The rest is relatively straightforward: read all files, skip the first two lines, massage TSV into quoted CSV, close the output descriptor. Hey presto!


```julia
quote_csv(s) = join(map(x -> "\"$x\"", split(s, ",")), ",")

headers = "date,time,x-edge-location,sc-bytes,c-ip,cs-method,cs(Host),cs-uri-stem,sc-status,cs(Referer),cs(User-Agent),cs-uri-query,cs(Cookie),x-edge-result-type,x-edge-request-id,x-host-header,cs-protocol,cs-bytes,time-taken,x-forwarded-for,ssl-protocol,ssl-cipher,x-edge-response-result-type,cs-protocol-version,fle-status,fle-encrypted-fields,c-port,time-to-first-byte,x-edge-detailed-result-type,sc-content-type,sc-content-len,sc-range-start,sc-range-end"

csv_output = open("logs/concatenated.csv", "w+")
write(csv_output, "$(quote_csv(headers))\n")

for file in glob("ELHTE4P8I823B*", "logs")
    open(file, "r") do io
        line = 0

        while !eof(io) 
            s = readline(io)
            line += 1

            if line < 3
                continue
            end

            s = split(s, "\t")
            write(csv_output, "$(quote_csv(s))\n")
        end
    end
end

close(csv_output)
```

Now we'll pack it all up into a neat little data frame so we can have our fun. Most of those columns are not really useful to us, and spilling some of those would be GDPR-bad. I could do this cleanup at the time of reading it from the original files, but I'm lazy and data frames have pretty cool facilities for lazy people.

Let's take a quick look at the data once we're done reading it:


```julia
removed_columns = ["x-edge-location", "c-ip", "cs(Host)", "cs(Referer)", "cs-uri-query", "cs(Cookie)", "x-edge-result-type", "x-edge-request-id", "x-host-header", "cs-bytes", "time-taken", "x-forwarded-for", "ssl-protocol", "ssl-cipher", "x-edge-response-result-type", "cs-protocol-version", "fle-status", "fle-encrypted-fields", "c-port", "time-to-first-byte", "x-edge-detailed-result-type", "sc-content-len", "sc-range-start", "sc-range-end"]

df = CSV.read("logs/concatenated.csv", DataFrame)

df = select!(df, Not(removed_columns))

show(sort(df, order(:date, rev=true)), allcols=true)
```

    39404×9 DataFrame
       Row │ date        time      sc-bytes  cs-method  cs-uri-stem  sc-status  cs(User-Agent)                     cs-protocol  sc-content-type 
           │ Date        Time      Int64     String7    String       Int64      String                             String7      String31        
    ───────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
         1 │ 2022-04-21  00:08:44     11434  GET        /                  200  Expanse%20indexes%20customers%E2…  https        text/html
         2 │ 2022-04-21  00:09:08       581  GET        /                  301  Expanse%20indexes%20customers%E2…  http         text/html
         3 │ 2022-04-21  00:56:01       377  GET        /index.xml         304  Mozilla/5.0%20(compatible;%20Min…  https        -
         4 │ 2022-04-21  00:20:30      2256  GET        /index.xml         200  FreshRSS/1.19.2%20(Linux;%20http…  https        application/xml
         5 │ 2022-04-21  00:25:46      2657  GET        /index.xml         200  Mozilla/5.0%20(compatible;%20Min…  https        application/xml
         6 │ 2022-04-21  00:42:21     11444  GET        /                  200  Expanse%20indexes%20customers%E2…  https        text/html
         7 │ 2022-04-21  01:53:44      4107  GET        /                  200  Mozilla/5.0%20(Windows%20NT%206.…  https        text/html
         8 │ 2022-04-21  01:54:06      2655  GET        /index.xml         200  Mozilla/5.0%20(compatible;%20Min…  https        application/xml
         9 │ 2022-04-21  01:20:35     11435  GET        /                  200  Expanse%20indexes%20customers%E2…  https        text/html
        10 │ 2022-04-21  01:40:37      2269  GET        /index.xml         200  FreshRSS/1.19.2%20(Linux;%20http…  https        application/xml
        11 │ 2022-04-21  01:11:37       581  GET        /                  301  Expanse%20indexes%20customers%E2…  http         text/html
       ⋮   │     ⋮          ⋮         ⋮          ⋮           ⋮           ⋮                      ⋮                       ⋮              ⋮
     39395 │ 2021-08-31  22:47:08       590  GET        /kefu.php          301  Mozilla/5.0%20(Macintosh;%20Inte…  http         text/html
     39396 │ 2021-08-31  22:47:11       588  GET        /im/h5/            301  Mozilla/5.0%20(Macintosh;%20Inte…  http         text/html
     39397 │ 2021-08-31  22:47:11       590  GET        /info.php          301  Mozilla/5.0%20(Macintosh;%20Inte…  http         text/html
     39398 │ 2021-08-31  22:47:17         0  GET        /im/h5/              0  Mozilla/5.0%20(Macintosh;%20Inte…  https        -
     39399 │ 2021-08-31  22:47:13       582  GET        /                  301  Mozilla/5.0%20(Linux;%20Android%…  http         text/html
     39400 │ 2021-08-31  22:47:11         0  GET        /im/                 0  Mozilla/5.0%20(Macintosh;%20Inte…  https        -
     39401 │ 2021-08-31  22:47:19       591  GET        /mtja.html         301  Mozilla/5.0%20(Macintosh;%20Inte…  http         text/html
     39402 │ 2021-08-31  22:29:07       399  HEAD       /                  301  go-resty/2.3.0%20(https://github…  http         text/html
     39403 │ 2021-08-31  22:29:08       320  HEAD       /                  200  go-resty/2.3.0%20(https://github…  https        text/html
     39404 │ 2021-08-31  23:46:57       582  GET        /                  301  Mozilla/5.0%20(Macintosh;%20PPC%…  http         text/html
                                                                                                                              39383 rows omitted

Already some interesting URIs in there back when the site was starting out... I suppose bots are gonna bot. Anyhow, now we can start checking through the data in earnest. First, as a quick litmus test, let's make sure that most requests we get actually end up satisfied. Quickest yardstick we can get would be probably status codes. Let's group by `sc-status`, count the rows and sort by the count.

```julia
status_group = groupby(df, ["sc-status"])
sort(
    combine(status_group, nrow => :count),
    [order(:count, rev = true)]
)
```

<div class="data-frame"><p>7 rows × 2 columns</p><table class="data-frame"><thead><tr><th></th><th>sc-status</th><th>count</th></tr><tr><th></th><th title="Int64">Int64</th><th title="Int64">Int64</th></tr></thead><tbody><tr><th>1</th><td>200</td><td>26249</td></tr><tr><th>2</th><td>301</td><td>6508</td></tr><tr><th>3</th><td>404</td><td>5033</td></tr><tr><th>4</th><td>304</td><td>1464</td></tr><tr><th>5</th><td>403</td><td>77</td></tr><tr><th>6</th><td>0</td><td>69</td></tr><tr><th>7</th><td>206</td><td>4</td></tr></tbody></table></div>



Well then! It seems that most our requestors come away with what they intended to get. I'm wondering about both 404 and 301 statuses. I think we oughtta drill down into what URIs were actually requested there. We'll do the exact same thing, but filter first.


```julia
show(
    sort(
        combine(
            groupby(filter("sc-status" => n -> n == 404, df), ["cs-uri-stem"]),
            nrow => :count
        ),
        [order(:count, rev = true)]
    ),
)
```

    458×2 DataFrame
     Row │ cs-uri-stem                        count 
         │ String                             Int64 
    ─────┼──────────────────────────────────────────
       1 │ /robots.txt                         2867
       2 │ /favicon.ico                         350
       3 │ /wp-login.php                        303
       4 │ /favicon.svg                         162
       5 │ /apple-touch-icon.png                125
       6 │ /image.png                           102
       7 │ /ads.txt                              46
       8 │ /humans.txt                           35
       9 │ /.env                                 30
      10 │ /.git/config                          18
      11 │ //wp-includes/wlwmanifest.xml         14
      ⋮  │                 ⋮                    ⋮
     449 │ /login                                 1
     450 │ /login.php                             1
     451 │ /login.aspx                            1
     452 │ /login/                                1
     453 │ /Login                                 1
     454 │ /login.html                            1
     455 │ /login.asp                             1
     456 │ /.aws                                  1
     457 │ /new/license.txt                       1
     458 │ /plugins/elfinder/connectors/php…      1
                                    437 rows omitted

Mixed bag, I suppose! Some completely legitimate requests - such as `robots.txt`, `ads.txt`, `humans.txt` and favicons, all of which should probably show up on my TODOs for Planet Golang. And then there's the script kiddie (or these days, more realistically, bot) stuff like looking for exposed credentials, login panels and Wordpress installations.

What's up with those 301s though?


```julia
show(
    sort(
        combine(
            groupby(filter("sc-status" => n -> n == 301, df), ["cs-uri-stem"]),
            nrow => :count
        ),
        [order(:count, rev = true)]
    ),
)
```

    691×2 DataFrame
     Row │ cs-uri-stem                        count 
         │ String                             Int64 
    ─────┼──────────────────────────────────────────
       1 │ /                                   3991
       2 │ /robots.txt                          478
       3 │ /wp-login.php                        300
       4 │ /favicon.ico                         245
       5 │ /ads.txt                              45
       6 │ /what.html                            45
       7 │ /humans.txt                           35
       8 │ /.env                                 33
       9 │ /style.css                            24
      10 │ /index.xml                            23
      11 │ /1.html                               23
      ⋮  │                 ⋮                    ⋮
     682 │ /info.php/_profiler/phpinfo            1
     683 │ /assets/elfinder/src/connectors/…      1
     684 │ /old/license.txt                       1
     685 │ /assets/plugins/elfinder/src/con…      1
     686 │ /admin/elfinder/src/connectors/p…      1
     687 │ /server-status                         1
     688 │ /.aws                                  1
     689 │ /new/license.txt                       1
     690 │ /plugins/elfinder/connectors/php…      1
     691 │ /118.html                              1
                                    670 rows omitted

Oh. It's... more of the same. Well, live and learn I suppose. (Side note - I'm checking out the entirety of those data frames, but they'd be _super_ boring to list here).

But these were all just stretches, right? We all know what I'm about. As a proponent of RSS, I wonder whether the HTML or the RSS version of the site is more popular! Also, I think we'll extract the month from our date and group on that so we can see the trend over time. Without further ado, let's add some columns to our DF.


```julia
using Dates

@chain df begin 
    @rtransform! :month = Dates.format(:date, "yyyy-mm")
    @rtransform! :category = :"sc-content-type" == "text/html" ? "html" : (:"sc-content-type" == "application/xml" ? "rss" : "none")
end

month_category = sort(
        combine(
            groupby(
                filter(
                    "sc-status" => n -> n == 200, filter(
                        "category" => n -> n == "rss" || n == "html", df
                    )
                ), ["month", "category"]),
            nrow => :count
        ),
        [order(:month), order(:category)]
    )

show(month_category)
```

    18×3 DataFrame
     Row │ month    category  count 
         │ String   String    Int64 
    ─────┼──────────────────────────
       1 │ 2021-08  html        192
       2 │ 2021-08  rss          10
       3 │ 2021-09  html       1221
       4 │ 2021-09  rss         469
       5 │ 2021-10  html       1433
       6 │ 2021-10  rss         593
       7 │ 2021-11  html       1605
       8 │ 2021-11  rss         647
       9 │ 2021-12  html       2113
      10 │ 2021-12  rss        1649
      11 │ 2022-01  html       2665
      12 │ 2022-01  rss        1241
      13 │ 2022-02  html       2544
      14 │ 2022-02  rss         998
      15 │ 2022-03  html       2795
      16 │ 2022-03  rss        1507
      17 │ 2022-04  html       1752
      18 │ 2022-04  rss        1223

Good, this is about what I was going for. And now, for my last trick... the same stuff, in plot form!

```julia
@df month_category plot(groupedbar(:month, :count, group = :category, bar_position = :stack))
```
    
![svg](/media/output_16_0.svg)
    

Hmph. Well, no dice - it's clear that HTML requests still dominate :) It is however heartening to see that people use the site and that it's gaining traction!

As I mentioned on Planet Golang itself, "planets" are slowly becoming a thing of the past. It's pretty much "curated this" and "algorithmic that" these days, and while I may not consider these the best ways to consume content, they are certainly prevalent. If you're interested in an unopinionated, anything-goes feed for Golang, however, I certainly recomment visiting [planetgolang.dev](https://planetgolang.dev) and checking it out yourself.
