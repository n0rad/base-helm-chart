import mergeAllOf from 'json-schema-merge-allof'
import $RefParser from "@apidevtools/json-schema-ref-parser";
import fs from 'fs';

try {
    let dereferencedSchema = await $RefParser.dereference("schema/root.schema.json");
    let mergedAllOfSchema = mergeAllOf(dereferencedSchema, {
        ignoreAdditionalProperties: true,
        resolvers: {
            defaultResolver: mergeAllOf.options.resolvers.title
        }
    });
    fs.writeFileSync('values.schema.json', JSON.stringify(mergedAllOfSchema));
    nullableTypes(mergedAllOfSchema)
    fs.writeFileSync('default-values.schema.json', JSON.stringify(mergedAllOfSchema));
} catch (err) {
    console.error(err);
    process.exit(1);
}

function nullableTypes(obj) {
    for (const key in obj) {
        if (key === "type") {
            if (typeof obj[key] == "string" && obj[key] !== "null") {
                obj[key] = [obj[key], "null"]
            } else if (Array.isArray(obj[key]) && !obj[key].includes("null")) {
                obj[key].push("null")
            }
        } else if (obj[key] instanceof Object && !(obj[key] instanceof Array)) {
            nullableTypes(obj[key])
        }
    }
}