package com.javet.demo;

import com.caoccao.javet.interop.NodeRuntime;
import com.caoccao.javet.interop.V8Host;
import com.caoccao.javet.interop.converters.JavetProxyConverter;
import com.caoccao.javet.interop.engine.JavetEngineConfig;
import com.caoccao.javet.values.reference.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@Slf4j
public class DemoApplication implements CommandLineRunner {

	public static void main(String[] args) {
		SpringApplication.run(DemoApplication.class, args);
	}

	@Override
	public void run(String... args) throws Exception {
		try (NodeRuntime runtime = V8Host.getNodeInstance().createV8Runtime()) {
			runtime.allowEval(true);
			runtime.setLogger(JavetEngineConfig.DEFAULT_JAVET_LOGGER);
			JavetProxyConverter converter = new JavetProxyConverter();
			runtime.setConverter(converter);
			V8ValueGlobalObject globalObject = runtime.getGlobalObject();
			runtime.getExecutor("""
					this.printHello = async (name, timeout = 1000) => {
						await new Promise((resolve) => {
							setTimeout(() => {
								console.log(`Hello, ${name}!`);
								resolve();
							}, timeout);
						});
						return 'Hello World!';
					};
					""").executeVoid();
			V8ValuePromise value = ((V8ValueFunction) globalObject.get("printHello")).call(null, "caoccao", 500);
			runtime.await();
			if (value.getState() == IV8ValuePromise.STATE_FULFILLED) {
				log.info("fulfilled result: {}", value.getResult());
			} else {
				V8ValueError e = value.getResult();
				log.info("rejected error: {}", e);
			}
		}
	}
}
