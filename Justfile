shellcheck:
    shellcheck -a -x $(find . -type f -name "*.sh") > ./shellcheck.txt

cloc:
    cloc . >/home/"$USER"/.hi.d/reports/cloc.txt
