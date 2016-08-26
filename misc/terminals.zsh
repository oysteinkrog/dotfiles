#!/bin/zsh
dir=$0:h
for term_array (
  'st true'
  'konsole true'
  'gnome-terminal false'
  'Terminal false'
  'terminal false'
  'terminator false'
  'urxvt-256color true -is +is'
  'uxterm true -bdc +bdc')
do
  opts=( $=term_array )
  term=$opts[1]
  array_args=$opts[2]
  opts[1,2]=()
  (( $#opts )) || opts=( '' )
  for opt in "${opts[@]}"
  do
    shcmd="echo $term $opt ; $dir/simpler ; read"
    if $array_args
    then
      cmd=( sh -c $shcmd )
    else
      cmd=( "sh -c ${(q)shcmd}" )
    fi
    tcmd=( $term $opt -e $cmd )
    $tcmd &
    sleep 0.5
  done
done
