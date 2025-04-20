LLM_QUICK_PROMPT="Answer in as few words as possible. Use a brief style with short replies, use only unicode for formulas and don't use any formatting ."
q(){
    noglob llm -s "$LLM_QUICK_PROMPT" "$*"
}

qe(){
    noglob llm -m openrouter/anthropic/claude-3.5-sonnet \
    -s "$LLM_QUICK_PROMPT" "$*"
}