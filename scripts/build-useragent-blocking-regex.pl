#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use Regexp::Assemble;

my @lines = readline DATA;
chomp @lines;
my $ra = Regexp::Assemble->new;
$ra->add(quotemeta $_) foreach @lines;
my $re = $ra->re;
say '^' . $re . '$';


__DATA__
Apache-HttpClient/4.4.1 (Java/1.8.0_102)
Apache-HttpClient/4.5.1 (Java/1.8.0_151)
Apache-HttpClient/4.5.1 (Java/1.8.0_45)
Apache-HttpClient/4.5.2 (Java/1.8.0_144)
Apache-HttpClient/4.5.2 (Java/1.8.0_151)
Apache-HttpClient/4.5.2 (Java/1.8.0_162)
Apache-HttpClient/4.5.2 (Java/1.8.0_60)
Apache-HttpClient/4.5.3 (Java/1.8.0_101)
Apache-HttpClient/4.5.3 (Java/1.8.0_112)
Apache-HttpClient/4.5.3-SNAPSHOT (Java/1.8.0_152)
Apache-HttpClient/4.5.3-SNAPSHOT (Java/1.8.0_73)
Apache-HttpClient/4.5.4 (Java/1.8.0_144)
Java/1.4.1_01
Java/1.7.0_04
Java/1.7.0_161
Java/1.7.0_51
Java/1.7.0_60
Java/1.7.0_80
Java/1.8.0_05
Java/1.8.0_121
Java/1.8.0_144
Java/1.8.0_151
Java/1.8.0_152
Java/1.8.0_181
Java/1.8.0_72
Java/1.8.0_74
Java/11.0.1
Mozilla/5.0
Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-CN; rv:1.9.1.1) Gecko/20090715 Firefox/3.5.1 LVS
Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-CN; rv:1.9.1.1) Gecko/20090715 Firefox/3.5.1 LVS inf-ssl-duty-scan
Mozilla/5.0 (compatible; BLEXBot/1.0; +http://webmeup-crawler.com/)
Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)
Mozilla/5.0 (compatible; DotBot/1.1; http://www.opensiteexplorer.org/dotbot, help@moz.com)
Mozilla/5.0 (compatible; Exabot/3.0; +http://www.exabot.com/go/robot)
Mozilla/5.0 (compatible; MJ12bot/v1.4.8; http://mj12bot.com/)
Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.0; Trident/5.0;  Trident/5.0)
Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Win64; x64; Trident/5.0)
Mozilla/5.0 (compatible; Nimbostratus-Bot/v1.3.2; http://cloudsystemnetworks.com)
Mozilla/5.0 (compatible; SemrushBot/3~bl; +http://www.semrush.com/bot.html)
Mozilla/5.0 (compatible; SeznamBot/3.2; +http://napoveda.seznam.cz/en/seznambot-intro/)
Mozilla/5.0 (compatible; SputnikBot/2.3; +http://corp.sputnik.ru/webmaster)
Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)
Mozilla/5.0 (compatible; Yeti/1.1; +http://naver.me/spd)
Mozilla/5.0 (compatible; special_archiver/3.1.1 +http://www.archive.org/details/archive.org_bot)"
SEMrushBot
Sogou web spider/4.0(+http://www.sogou.com/docs/help/webmasters.htm#07)
make-fetch-happen/2.6.0 (+https://npm.im/make-fetch-happen)
python-requests/2.14.2
