<article class="message {% if class %}{{class | safe}}{% endif %}">
  {% if title %}
  <div class="message-header">
   {{ title | markdown }}
  </div>
  {% endif %}
  <div class="message-body">
    {{ body | markdown }}
  </div>
</article>