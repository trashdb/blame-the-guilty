curl -s https://api.github.com/users/alvaro-lopez-ej = 197886905
curl -s https://api.github.com/users/trashdb = 296179642

curl -X POST "https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github" \
-H "Content-Type: application/json" \
-d '{
"action": "completed",
"workflow_run": {
"id": 12345678,
"conclusion": "failure",
"pull_requests": [
{
"merged_by": {
"id": 296179642,
"login": "trashdb"
}
}
]
},
"repository": {
"full_name": "trashdb/blame-the-guilty"
},
"sender": {
"id": 296179642,
"login": "trashdb"
}
}'