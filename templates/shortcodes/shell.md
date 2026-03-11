
```{{ dialect }}
{{ command  }}
```

{% if body %}
```
{{ body | safe }}
```
{% endif %}