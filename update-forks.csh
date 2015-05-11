#!/bin/csh

foreach i (`cat forks`)
  ./update-fork.sh $i
end
