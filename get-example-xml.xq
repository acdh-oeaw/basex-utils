import module namespace util = "https://www.oeaw.ac.at/acdh/util/util" at "acdh-utils/util.xqm";

let $atomDocs := for $fruit in $util:unit-test-fruit-names
let $xmlName := upper-case(substring($fruit, 1, 1))||substring($fruit, 2)||".atom",
    $dbpediaUrl := "https://dbpedia.org/data/"||$xmlName 
(: return $dbpediaUrl :)
return parse-xml(replace(fetch:text($dbpediaUrl, "UTF-8"), '&amp;', '&amp;amp;')
              => replace('\t', ''))
return zip:zip-file(<zip:file href="{file:parent(static-base-uri())||'fixtures/atoms.zip'}">
{ for $doc at $pos in $atomDocs
  return <zip:entry name="{$util:unit-test-fruit-names[$pos]||'.atom'}">{$doc}</zip:entry>
}
</zip:file>)