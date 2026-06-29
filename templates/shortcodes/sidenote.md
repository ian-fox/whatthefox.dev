<span class="sidenote"><label
        id="sidenote-label-{{ nth }}"
        for="sidenote-body-{{ nth }}"
        class="sidenote-label"
    ><a><sup>{{ nth }}</sup></a>
    </label>
    <small
        id="sidenote-body-{{ nth }}"
        class="sidenote-body"
    >
        <label for="sidenote-label-{{ nth }}"><sup>{{ nth }}</sup></label> {{body | safe}}
    </small>
</span>