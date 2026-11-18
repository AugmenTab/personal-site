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
