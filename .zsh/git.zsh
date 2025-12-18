# View current PR in github
alias vpr='gh pr view --web'

# Fuzzy search pr list
alias fpr='gh pr list | fzf --preview "gh pr diff --color=always {+1}" |  { read first rest ; echo $first ; } | xargs gh pr checkout'
