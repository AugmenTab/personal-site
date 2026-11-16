-- | The overview's small cluster of facts: label and value pairs. (Brigid
-- does not accept the @<div>@ grouping inside @<dl>@ that HTML allows, so
-- the pairs are siblings and CSS places each pair in its own column.)
factList :: E.ValidChild E.DescriptionList parent grandparent
         => [Fact] -> E.ChildHTML parent grandparent
factList facts =
  E.dl [ A.class_ "dossier-facts" ]
    (concat
       [ [ E.dt [] [ E.text (factLabel f) ]
         , E.dd [] [ E.text (factValue f) ]
         ]
       | f <- facts
       ])
