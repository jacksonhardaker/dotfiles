function unminify() {
    # Check if Deno is available
    if ! command -v deno &> /dev/null; then
        echo "❌ Deno is not installed."
        echo "To install it, run:"
        echo "  curl -fsSL https://deno.land/install.sh | sh"
        return 1
    fi

    if [[ $# -lt 3 ]]; then
        echo "Usage: unminify <map_file> <line> <column>"
        return 1
    fi
    
    # We use 'deno run -' to read the script from stdin.
    # We pass the arguments "$@" after the '-' so Deno.args picks them up.
    # usage: deno run [flags] - [args]
    # --no-config ensures Deno ignores local package.json/deno.json files
    deno run --no-config -A - "$1" "$2" "$3" <<'EOF'
import { SourceMapConsumer } from "npm:source-map@0.7.4";

const args = Deno.args;
// Note: In this embedded context, we assume args are passed correctly via CLI
if (args.length < 3) {
    console.error('%cUsage: unminify <file.map> <line> <column>', 'color: red');
    Deno.exit(1);
}

const [mapFile, inputLine, inputCol] = args;

try {
    const rawMap = await Deno.readTextFile(mapFile);
    const jsonMap = JSON.parse(rawMap);
    
    const consumer = await new SourceMapConsumer(jsonMap);
    
    const pos = consumer.originalPositionFor({
        line: parseInt(inputLine),
        column: parseInt(inputCol)
    });

    if (!pos.source) {
        console.log('%cNo matching source location found.', 'color: orange');
        consumer.destroy();
        Deno.exit(0);
    }

    // Print Results
    console.log('\n%c✔ Location Resolved:', 'font-weight: bold; color: green');
    console.log(`  File:   %c${pos.source}`, 'color: cyan');
    console.log(`  Line:   %c${pos.line}`, 'color: yellow');
    console.log(`  Column: %c${pos.column}`, 'color: yellow');
    if (pos.name) console.log(`  Symbol: %c${pos.name}`, 'color: magenta');

    // Context
    if (consumer.sourcesContent) {
        const sourceIndex = consumer.sources.indexOf(pos.source);
        if (sourceIndex >= 0 && consumer.sourcesContent[sourceIndex]) {
            console.log('\n%cCode Context:', 'font-weight: bold');
            const content = consumer.sourcesContent[sourceIndex];
            const lines = content.split(/\r?\n/);
            const targetLine = (pos.line || 1) - 1;
            
            const start = Math.max(0, targetLine - 2);
            const end = Math.min(lines.length - 1, targetLine + 2);

            for (let i = start; i <= end; i++) {
                const isTarget = i === targetLine;
                const prefix = isTarget ? '>' : ' ';
                const lineNum = (i + 1).toString().padEnd(4);
                
                const color = isTarget ? "background-color: green; color: black" : "color: gray";
                console.log(`%c ${prefix} ${lineNum} ${lines[i]}`, color);
            }
        }
    }
    console.log('');
    consumer.destroy();

} catch (err) {
    console.error(`%cError: ${err.message}`, 'color: red');
    Deno.exit(1);
}
EOF
}
