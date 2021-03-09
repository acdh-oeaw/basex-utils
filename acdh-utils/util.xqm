xquery version "3.0";
(:
 : Copyright (c)2020 Omar Siam
 : Copyright (c)2019 Thomas Klampfl
 : Copyright (c)2020 ACDH-CH ÖAW
 :
 : Permission is hereby granted, free of charge, to any person obtaining a copy
 : of this software and associated documentation files (the "Software"), to deal
 : in the Software without restriction, including without limitation the rights
 : to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 : copies of the Software, and to permit persons to whom the Software is
 : furnished to do so, subject to the following conditions:

 : The above copyright notice and this permission notice shall be included in
 : all copies or substantial portions of the Software.

 : THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 : IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 : FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 : THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 : LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 : OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 : THE SOFTWARE.
 :)
  
(:~ 
 :  This module provides the utility functions used at the ACDH-CH when writing BaseX Software.
 :  This modules raise errors in this namespace https://www.oeaw.ac.at/acdh/util/error
 :
 :  TODO:
 :  <ul>
 :    <li>The eval(s) functions are missing a watchdog feature that terminates the started
          jobs if the starting query is interupted or destroyed by something.</li>
 :  </ul>
 :
 :  @author Omar Siam, 
 :  @since June 1, 2018
 :  @version 1.0
 :)
 
module namespace _ = "https://www.oeaw.ac.at/acdh/util/util";
  
declare namespace _err = "https://www.oeaw.ac.at/acdh/util/error";

import module namespace jobs = "http://basex.org/modules/jobs";
import module namespace l = "http://basex.org/modules/admin";

(:~ 
 :  This is set to the path of this module.
 :  This is used to construct better error messages.
 :  The ad-hoc XQuery snippets evaluated here will have a "location": $util:basePath.
 :)
declare variable $_:basePath := string-join(tokenize(static-base-uri(), '/')[last() > position()], '/');
(:~ 
 :  This is the file name of this module.
 :  Unused here at the moment.
 :)
declare variable $_:selfName := tokenize(static-base-uri(), '/')[last()];
(:~ 
 :  This is the name of an attribute used for sorting dehydrated nodes.
 :  It should be unique and not used by any other code.
 :)
declare variable $_:vleUtilSortKey := "vutlsk";

(:~ 
 :  Executes a reading query as separate job so without any locks in the calling XQuery.
 :  Shortcut for eval with $dontCheckQuery = false().
 :
 :  @param $query Query to execute.
 :  @param $bindings Map with bindings for external variables contained in the query
 :  @param $jobName A discriptive name for the query so it can be identified
 :  @return Result of the query.
 :          Reraises any exceptions that the query may have raised.
 :)
declare function _:eval($query as xs:string, $bindings as map(*)?, $jobName as xs:string) as item()* {
  _:eval($query, $bindings, $jobName, false())
};

(:~ 
 :  Executes any query as separate job so without any locks in the calling XQuery.
 :  For potentially dangerous queries $dontCheckQuery has to be true()
 :  Details are implemented in start-eval-job.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:start-eval-job;_:start-eval-job
 :  @param $query Query to execute.
 :  @param $bindings Map with bindings for external variables contained in the query.
 :  @param $jobName A discriptive name for the query so it can be identified.
 :  @param $dontCheckQuery Allow updating and more destructive XQueries.
 :  @return Result of the query.
 :          Reraises any exceptions that the query may have raised.
 :)
declare function _:eval($query as xs:string, $bindings as map(*)?, $jobName as xs:string, $dontCheckQuery as xs:boolean) as item()* {
    let (: $log := l:write-log($query, 'INFO'), :)
        $j := _:start-eval-job($query, $bindings, $jobName, $dontCheckQuery, 0), $_ := jobs:wait($j)   
    return jobs:result($j)
};

(:~ 
 :  Implementation detail: Executes a query as separate job.
 :  Uses jobs:eval() with caching to execute $query truely independently of the calling XQuery
 :  including locks and indexes if the optimizer recognizes the databases in the
 :  probably much shorter (sub)query.
 :  Tries to create meaningful names and base-uris for $query.
 : 
 :  @param $query Query to execute.
 :  @param $bindings Map with bindings for external variables contained in the query.
 :  @param $jobName A descriptive name of the job $query does
 :  @param $dontCheckQuery Allow updating and more destructive XQueries.
 :  @param $subJobNumber An integer used to differentiate very similar jobs.
 :  @return The job ID which jobs:* function take as an argument.
 :          Raises an _err:too-many-parallel-requests if there are currently more jobs running
 :          then the maximum of parallel jobs configured for BaseX.
 :          Will reraise any error while executing $query.
 :)
declare %private function _:start-eval-job($query as xs:string, $bindings as map(*)?, $jobName as xs:string, $dontCheckQuery as xs:boolean, $subJobNumber as xs:integer) as xs:string {
    let $too-many-jobs := if (count(jobs:list()) >= xs:integer(db:system()//parallel)) then 
                          error(xs:QName('_err:too-many-parallel-requests'), 'Too many parallel requests! (>='||db:system()//parallel||')') else (),
        $query-is-sane := $dontCheckQuery or _:query-is-sane($query)
        (: , $log := l:write-log($jobName||'-'||$subJobNumber||'-'||jobs:current()||': '||$query, 'DEBUG') :)
        return jobs:eval($query, $bindings, map {
          'cache': true(),
          'id': 'vleserver:'||$jobName||'-'||$subJobNumber||'-'||jobs:current(),
          'base-uri': $_:basePath||'/vleserver_'||$jobName||'-'||$subJobNumber||'.xq'})
};

(:~
 :  Implementation detail: Check whether this XQuery uses updating or other functions that can be destructive.
 :  
 :  <ul>
 :    <li>Blocks updating queries</li>
 :    <li>Blocks queries that use xquery:eval()</li>
 :    <li>Blocks queries that use http:send-request()</li>
 :  </ul>
 :
 :  @param $query The query to check.
 :  @return True if the function does not use anything unwanted.
 :          If there is unwanted code in the XQuery this raises an _err:dubious-query.
 :)
declare %private function _:query-is-sane($query as xs:string) as xs:boolean {
   let $error-class := xs:QName('_:dubious-query'),
      $parsed-query := try {
        xquery:parse($query, map {'pass': true()})
      } catch * {error($error-class, ``[Query error:
      `{$query}` 
      `{$err:code}` `{$err:description}` `{$err:line-number}`/`{$err:column-number}`]``)},
      (: $log := l:write-log(serialize($parsed-query), 'DEBUG'), :)
      $contains-update := if ($parsed-query/@updating ne 'false') then error($error-class, 'Query is updating: '||$query) else (),
      $contains-xquer-eval := if (exists($parsed-query//XQueryEval) or exists($parsed-query//XQueryInvoke)) then error($error-class, 'Query contains xquery:eval: '||$query) else (),
      $contains-jobs-eval := if (exists($parsed-query//JobsEval) or exists($parsed-query//JobsInvoke)) then error($error-class, 'Query contains jobs:eval: '||$query) else (),
      $contains-http-request := if (exists($parsed-query//HttpSendRequest)) then error($error-class, 'Query contains http:send-request: '||$query) else ()
  return true()
};

(:~ 
 :  Executes queries as separate jobs without locks in the calling XQuery.
 :  Uses jobs:eval() with caching to execute batches of $queries truely independently of the
 :  calling XQuery including locks and indexes if the optimizer recognizes the databases in the
 :  probably much shorter (sub)query.
 :  Tries to create meaningful names and base-uris for each query in $queries.
 :  Uses a small random delay to not start all queries at once.
 :  Logs if execution needs more than 100ms.
 :  The main use of this function is to query a set of similar databases with pre created
 :  XQueries that contain any database name as string literal.
 :  This is easy to achieve with the XQuery 3.1 String constructors.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:start-eval-job;_:start-eval-job
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:get-results-or-errors;_:get-results-or-errors
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:throw-on-error-in-returns;_:throw-on-error-in-returns
 :  @param $queries Queries to execute.
 :  @param $bindings Map with bindings for external variables contained in the query.
 :  @param $jobName A descriptive name of the job $query does
 :  @param $dontCheckQuery Allow updating and more destructive XQueries.
 :  @return The job ID which jobs:* function take as an argument.
 :          Raises an _err:too-many-parallel-requests if there are currently more jobs running
 :          then the maximum of parallel jobs configured for BaseX.
 :          Will reraise any error while executing $queries.
 :)
declare function _:evals($queries as xs:string+, $bindings as map(*)?, $jobName as xs:string, $dontCheckQuery as xs:boolean) as item()* {
    (: WARNING: Clean up code is missing. If queries come in too fast (below 100 ms between each) or too many (more than 10 is not testet)
       batch-size may go down to 0 and/or the _err:too-many-parallel-requests error may show :)
    let $start := prof:current-ns(),
        $randMs := random:integer(100),
        $randSleep := prof:sleep($randMs),
        $batch-size := _:get-batch-size(),
        $batches := (0 to xs:integer(ceiling(count($queries) div $batch-size))),
        (: , $log := l:write-log('$randMs := '||$randMs||' $batch-size := '||$batch-size, 'DEBUG') :)
        $ret := for $batch-number in $batches
                let $js := subsequence($queries, $batch-number * $batch-size + 1, $batch-size)!_:start-eval-job(., $bindings, $jobName, $dontCheckQuery, xs:integer($batch-size * $batch-number + position()))
                  , $_ := $js!jobs:wait(.)
                (:, $status := jobs:list-details()[@id = $js]
                  , $log := $status!l:write-log('Job '||./@id||' duration '||seconds-from-duration(./@duration)*1000||' ms') :)
                return _:get-results-or-errors($js)
      , $runtime := ((prof:current-ns() - $start) idiv 10000) div 100
      , $log := if ($runtime > 100) then l:write-log('Batch execution of '||count($queries)||' jobs for '||$jobName||' took '||$runtime||' ms') else ()
      (: , $logMore := l:write-log(serialize($ret[. instance of node()]/self::_:error, map{'method': 'xml'})) :)
    return _:throw-on-error-in-returns($ret)
};

(:~ 
 :  Set the batch size to 1/3 of all possible parallel jobs
 :
 :  @return Number of jobs in on batch.
 :)
declare function _:get-batch-size() as xs:integer {
  xs:integer(floor((xs:integer(db:system()//parallel) - count(jobs:list())) * 1 div 3))
};

(:~ 
 :  Get results or errors for a sequence of job IDs.
 :  Gets all results of a sequence of jobs.
 :  If there were errors raised they are encoded and also returned.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:throw-on-error-in-returns;_:throw-on-error-in-returns
 :  @param $js Job IDs.
 :  @return The results of the jobs or encoded errors if there were any.
 :)
declare function _:get-results-or-errors($js as xs:string*) {
   $js!(try { jobs:result(.) }
        catch * {
                  <_:error>
                    <_:code>{$err:code}</_:code>
                    <_:code-namespace>{namespace-uri-from-QName($err:code)}</_:code-namespace>
                    <_:description>{$err:description}</_:description>
                    <_:value>{$err:value}</_:value>
                    <_:module>{$err:module}</_:module>
                    <_:line-number>{$err:line-number}</_:line-number>
                    <_:column-number>{$err:column-number}</_:column-number>
                    <_:additional>{$err:additional}</_:additional>
                  </_:error>
                })
};

(:~ 
 :  Raises an error if there were any reported in the encoded results passed to this function.
 :  Gets all results of a sequence of jobs.
 :  If there were errors raised they are encoded and also returned.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:get-results-or-errors;_:get-results-or-errors
 :  @param $ret Some returned results from multiple jobs.
 :  @return The results of the jobs.
 :          Raises errors encoded in $ret.
 :)
declare function _:throw-on-error-in-returns($ret) {
if (exists($ret[. instance of node()]/self::_:error))
then ($ret[. instance of node()]/self::_:error)[1]!error(QName(./_:code-namespace, ./_:code),
          ($ret[. instance of node()]/self::_:error)[1]/_:description,
          string-join($ret[. instance of node()]/self::_:error/_:additional, '&#x0a;'))
else $ret  
};


(:~ 
 :   Return doc($fn) or if it cannot be resolves doc($default) without any locks in the calling query.
 :
 :   @param $fn A filename doc() and doc-available() can usually resolve.
 :   @param $default A filename doc() can always open.
 :   @return The contents of the opened document as in memory copy.
 :)
declare function _:get-xml-file-or-default($fn as xs:string, $default as xs:string) as document-node() {
   _:get-xml-file-or-default($fn, $default, true())
};

(:~
 :  Executes one query and binds a sequence of $batch-size items in sequence $sequencKey of $bindings per job.
 :  For example with seqenceKey := 'aKey':
 :  <code>map { 'aKey': (&lt;a/>,&lt;b/>)}</code>
 :
 :  If $batch-size is one two jobs are executed with &lt;a/> and &lt;b/> bound respectively,
 :  if $batch-size is two one job is executed with (&lt;a/>,&lt;b/>) bound
 :  and so on.
 :  
 :  @param $query A query with at least one external variable $sequenceKey
 :  @param $bindings Map with bindings for external variables contained in the query.
 :  @param $sequenceKey The name of the key in bindings which should be split $batch-size per job.
 :  @param $bach-size The maximum number of jobs this query should create simultaneously.
 :  @param $jobName A descriptive name of the job $query does
 :  @param $dontCheckQuery Allow updating and more destructive XQueries.
 :  @return The job ID which jobs:* function take as an argument.
 :          Will reraise any error while executing $queries.
 :)
declare function _:evals($query as xs:string, $bindings as map(*)?, $sequenceKey as xs:string, $batch-size as xs:integer, $jobName as xs:string, $dontCheckQuery as xs:boolean) as item()* {
      (: WARNING: Clean up code is missing. If queries come in too fast (below 100 ms between each) or too many (more than 10 is not testet)
       batch-size may go down to 0 and/or the _err:too-many-parallel-requests error may show :)
    let $start := prof:current-ns(),
        $randMs := random:integer(100),
        $randSleep := prof:sleep($randMs),
        $batches := (0 to xs:integer(ceiling(count($bindings($sequenceKey)) div $batch-size)) - 1),
     (: $log := l:write-log('$randMs := '||$randMs||' $batch-size := '||$batch-size, 'DEBUG'), :)
        $ret := for $batch-number at $batch-pos in $batches
                let $batch-bindings := map:merge((map {$sequenceKey: subsequence($bindings($sequenceKey), $batch-number * $batch-size + 1, $batch-size)}, $bindings)),
                 (: $log := l:write-log(serialize($batch-bindings, map {'method': 'basex'}), 'DEBUG'), :)
                    $js := _:start-eval-job($query, $batch-bindings, $jobName, $dontCheckQuery, xs:integer($batch-size * $batch-number + $batch-pos))
                  , $_ := $js!jobs:wait(.)
                (:, $status := jobs:list-details()[@id = $js]
                  , $log := $status!l:write-log('Job '||./@id||' duration '||seconds-from-duration(./@duration)*1000||' ms') :)
                return _:get-results-or-errors($js)
      , $runtime := ((prof:current-ns() - $start) idiv 10000) div 100,
        $log := if ($runtime > 100) then l:write-log('Batch execution of '||count($bindings($sequenceKey))||' jobs for '||$jobName||' took '||$runtime||' ms') else ()
    return _:throw-on-error-in-returns($ret)
};

(:~ 
 :   Return doc($fn) or if it cannot be resolves doc($default) without any locks in the calling query.
 :   If there is a way to know when $fn is definitly not there this can be passed in $fn-is-valid.
 :
 :   @param $fn A filename doc() and doc-available() can usually resolve.
 :   @param $default A filename doc() can always open.
 :   @param $fn-is-valid Whether $fn is tried at all
 :   @return The contents of the opened document as in memory copy.
 :)
declare function _:get-xml-file-or-default($fn as xs:string, $default as xs:string, $fn-is-valid as xs:boolean) as document-node() {
  let $q := if ($fn-is-valid) then ``[if (doc-available("`{$fn}`")) then doc("`{$fn}`") else doc("`{$default}`")]`` else
            ``[doc("`{$default}`")]``,
      $jid := jobs:eval($q, (), map {'cache': true(), 'base-uri': $_:basePath||'/'}), $_ := jobs:wait($jid)
  return jobs:result($jid)    
};

(:~
 :   Reduce a result of an XQuery to references of DB nodes.
 :
 :   @see https://www.oeaw.ac.at/acdh/util/util;_:hydrate;_:hydrate
 :   @param $nodes Nodes to turn into references to them
 :   @param $data-extractor-xquery A function that extracts some attribute from the nodes
 :          and makes it available in the reference data directly e. g. for sorting
 :   @return References to the nodes. The result is not sorted, most probably document order applies
 :)
declare function _:dehydrate($nodes as node()*, $data-extractor-xquery as function(node()) as attribute()*?) as element(_:dryed)* {
  for $nodes_in_db in $nodes
  group by $db_name := _:db-name($nodes_in_db)
  let $pres := db:node-pre($nodes_in_db)
  return (# db:copynode false #) { <_:dryed db_name="{$db_name}" order="none" created="{current-dateTime()}">
  {for $n at $i in $nodes_in_db
    let $extracted-attrs := try {
      $data-extractor-xquery($n)
    } catch * {
      '  _error_: '||$err:description
    }
    return <_:d pre="{$pres[$i]}" db_name="{$db_name}">{$extracted-attrs}</_:d>
  }
  </_:dryed> }
};

(:~
 : Get the db name containing a particular node.
 : BaseX' db:name causes global read lock.
 :
 : @param $n A node
 : @return Name of the DB containing the node $n.
 :)
declare function _:db-name($n as node()) as xs:string {
  replace($n/base-uri(), '^/([^/]+)/.*$', '$1')
};

(:~
 :  Fetch the real XML data from databases according to $dryed references.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:dehydrate;_:dehydrate 
 :  @param $dryed References to data in some BaseX database
 :  @return The actual XML data from the databases.
 :)
declare function _:hydrate($dryed as element(_:d)+) as node()* {
  let $queries := for $d in $dryed
      let $db_name := $d/@db_name
      group by $db_name
      let $pre_seq := '('||string-join($d/@pre, ', ')||')',
          $sort_key_seq := '("'||string-join($d/@*[local-name() = $_:vleUtilSortKey]!
            (replace(., '"', '&amp;quot;', 'q') => replace('&amp;([^q])', '&amp;amp;$1')), '","')||'")'
      return ``[declare namespace  _ = "https://www.oeaw.ac.at/acdh/tools/vle/util";
    for $pre at $i in `{$pre_seq}`
    return <_:h db_name="`{$db_name}`" pre="{$pre}" `{$_:vleUtilSortKey}`="{`{$sort_key_seq}`[$i]}">{db:open-pre("`{$db_name}`", $pre)}</_:h>
  ]``
  return _:evals($queries, (), 'util:hydrate', false())
};

(:~
 :  Fetch the real XML data from databases according to $dryed references.
 :
 :  @see https://www.oeaw.ac.at/acdh/util/util;_:dehydrate;_:dehydrate 
 :  @param $dryed References to data in some BaseX database
 :  @param $filter_code A XQuery function
 :         declare function filter($nodes as node()*) as node()* {()};
 :         used to filter the data fetched from BaseX databases usung the references in $dryed
 :  @return The actual XML data from the databases.
 :)
declare function _:hydrate($dryed as element(_:d)+, $filter_code as xs:string) as node()* {
  let $queries := for $d in $dryed
      let $db_name := $d/@db_name
      group by $db_name
      let $pre_seq := '('||string-join($d/@pre, ',')||')',
          $sort_key_seq := '("'||string-join($d/@*[local-name() = $_:vleUtilSortKey]!
            (replace(., '"', '&amp;quot;', 'q') => replace('&amp;([^q])', '&amp;amp;$1')), '","')||'")',
          $assert-seqs-match := if (count($d/@pre) ne count($d/@*[local-name() = $_:vleUtilSortKey]!xs:string(.)))
            then error(xs:QName('_:seq_mismatch'), 'pre and sort key don''t match')
            else ()
      return ``[declare namespace  _ = "https://www.oeaw.ac.at/acdh/tools/vle/util";
    `{$filter_code}`
    for $pre at $i in `{$pre_seq}`
    return <_:h db_name="`{$db_name}`" pre="{$pre}" `{$_:vleUtilSortKey}`="{`{$sort_key_seq}`[$i]}">{local:filter(db:open-pre("`{$db_name}`",  $pre))}</_:h>
  ]``
  return _:evals($queries, (), 'util:hydrate-and-filter', false())
};

(:~ 
 :   Try to get the correct scheme and hostname as seen by the reverse proxy
 :
 :   @return scheme://hostname:port/
 :)
declare function _:get-public-scheme-and-hostname() as xs:string {
  let $forwarded-hostname := if (contains(request:header('X-Forwarded-Host'), ',')) 
                               then substring-before(request:header('X-Forwarded-Host'), ',')
                               else request:header('X-Forwarded-Host'),
      $urlScheme := if ((lower-case(request:header('X-Forwarded-Proto')) = 'https') or 
                        (lower-case(request:header('Front-End-Https')) = 'on')) then 'https' else 'http',
      $port := if ($urlScheme eq 'http' and request:port() ne 80) then ':'||request:port()
               else if ($urlScheme eq 'https' and not(request:port() eq 80 or request:port() eq 443)) then ':'||request:port()
               else ''
  return $urlScheme||'://'||($forwarded-hostname, request:hostname())[1]||$port
};

(:~ 
 :   Use the X-Forwarded-Request-Uri custom request header to get the correct base URI as seen by the reverse proxy
 :   
 :   @return Either the base URI as seen by the reverse proxy or request:path() reported by jetty.
 :)
declare function _:get-base-uri-public() as xs:string {
  (: FIXME: this is to naive. Works for ProxyPass / to /exist/apps/cr-xq-mets/project
     but probably not for /x/y/z/ to /exist/apps/cr-xq-mets/project. Especially check the get module. :)
  let $xForwardBasedPath := (request:header('X-Forwarded-Request-Uri'), request:path())[1]
  return _:get-public-scheme-and-hostname()||$xForwardBasedPath
};

(:~
 :   Decodes the user name and password passed in Basic Auth.
 :   
 :   @param $encoded-auth Basic Auth header string Base64 encoded
 :   @return user name:password
 :)
declare function _:basic-auth-decode($encoded-auth as xs:string) as xs:string {
  (: Mostly ASCII/ISO-8859-1. Can be UTF-8. See https://stackoverflow.com/a/7243567. 
     Postman encodes ISO-8859-1 :)
  let $base64 as xs:base64Binary := xs:base64Binary(replace($encoded-auth, '^Basic ', ''))
  return try {
    convert:binary-to-string($base64, 'UTF-8')
  } catch convert:string {
    convert:binary-to-string($base64, 'ISO-8859-1')
  }
};

declare variable $_:unit-test-fruit-names := 
("apple", "apricot", "banana", "blueberry", "cherry", "coconut", "date", "elderberry", "fig",
 "grapefruit", "guava", "kiwifruit", "lime", "lychee");

declare %unit:before %updating function _:zzz-unit-test-before() {
   for $dbName in $_:unit-test-fruit-names
   return db:create('__test__'||$dbName, zip:xml-entry(file:parent(file:parent(static-base-uri()))||'fixtures/atoms.zip', $dbName||'.atom'), $dbName||'.atom')
};

declare %unit:test function _:basic-auth-decode-test() {
  unit:assert-equals(_:basic-auth-decode("Basic VGhpcyBpcyDhOlSnc3QmcGFzc3dvcmQ="), "This is á:T§st&amp;password", "Basic Auth decoding failed.")
};

declare %unit:test %unit:ignore("needs HTTP connection") function _:get-base-uri-public-test() {};

declare %unit:test %unit:ignore("needs HTTP connection") function _:get-public-scheme-and-hostname-test() {};

declare %unit:test function _:eval-test() {
  unit:assert-equals(jobs:list-details()[(@reads, @writes) = '(global)'], (), "Cannot test unless there are no global locks."),
unit:assert-equals(string-join((let $jid := jobs:eval(``[declare variable $dbName external;
collection($dbName)//*:abstract[@xml:lang="en"]]``, map {'dbName': '__test__apple'}, map {'cache': true()}),
      $_ := jobs:wait($jid),
      $details := jobs:list-details()
  return ($details[@id=$jid]/@reads, jobs:result($jid))[1],
  let $jid := jobs:eval(``[import module namespace util = "https://www.oeaw.ac.at/acdh/util/util" at "util.xqm";
util:eval("collection('"||"__test__apple"||"')//*:abstract[@xml:lang='en']", (), "util-eval-test")]``,(), map {'cache': true()}),
      $_ := jobs:wait($jid),
      $details := jobs:list-details()
  return ($details[@id=$jid]/@reads, jobs:result($jid))[1]), ' '), "(global) (none)", "Read locking of queries is not (global) (none)")
};

declare %unit:after %updating function _:zzz-unit-test-after() {
  for $dbName in $_:unit-test-fruit-names
  return db:drop('__test__'||$dbName)
};