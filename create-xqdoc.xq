xquery version "3.1";
(: xqdoc-display can be found at https://github.com/acdh-oeaw/xqdoc/releases/download/v1.0/xqdoc-display-1.0.xar.
   You can install this using the GUI client 'Options->Packages->Install from URL' for example.
   This script would not be possible without using jobs:eval.
   * Data created in an updating query and stored in database cannot be used in that same query.
   * xqdoc-display:get-module-html creates a read lock for xqdoc collection/DB at least
     so cannot run while something is stored in that collection/DB
 :)
import module namespace util = "https://www.oeaw.ac.at/acdh/util/util" at "acdh-utils/util.xqm";

util:eval(``[import module namespace xqdoc-display="http://www.xqdoc.org/1.0/display";
xqdoc-display:cache-xqdocs("`{file:parent(static-base-uri())}`")]``, (), "cache-util-xqdoc", true()),
let $outFile := file:parent(static-base-uri())||"xqdoc.html"
return file:write-text(
  $outFile,
  serialize(
  util:eval(``[import module namespace xqdoc-display="http://www.xqdoc.org/1.0/display";
xqdoc-display:get-module-html("https://www.oeaw.ac.at/acdh/util/util", true())]``, (), "cache-util-xqdoc", true()),
  map {"method": "html"}
))