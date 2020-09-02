#!/bin/bash

while true;
do
  echo "1. Show disk usage"
  echo "2. Show system uptime"
  echo "3. Show the users logged into the system."
  echo
  read -p "What would you like to do? (Enter q to quit.) $" option
  case "$option" in
    1)
      df
      echo
      ;;
    2)
      uptime
      echo
      ;;
    3)
      who
      echo
      ;;
    q)
      echo "Goodbye!"
      echo
      break
      ;;
    *)
      echo "Invalid option"
      echo
      ;;
  esac
done
