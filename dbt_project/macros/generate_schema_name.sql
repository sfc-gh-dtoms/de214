{#
    Build every model into the target schema (DEV or PROD) as-is.

    dbt's default prefixes a model's custom schema onto the target schema
    (e.g. DEV_staging). For this demo we keep ALL models in the bare target
    schema and use object-name prefixes (stg_ / mart_ / sv_) as data zones,
    so the same code deploys cleanly to DEV and PROD.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}
