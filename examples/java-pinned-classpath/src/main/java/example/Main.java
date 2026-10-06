package example;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** Uses a dependency, so the classpath below is load bearing rather than decorative. */
public final class Main {
    private static final Logger LOG = LoggerFactory.getLogger(Main.class);

    public static void main(String[] args) {
        LOG.info("compiled and run by daukle");
        System.out.println("hello from " + Main.class.getName());
    }
}
