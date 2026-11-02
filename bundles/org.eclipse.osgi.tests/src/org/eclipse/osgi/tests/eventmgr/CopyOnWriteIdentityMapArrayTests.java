/*******************************************************************************
 * Copyright (c) 2026 Contributors to the Eclipse Foundation.
 *
 * This program and the accompanying materials are made available under the terms
 * of the Eclipse Public License 2.0 which accompanies this distribution, and is
 * available at https://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *******************************************************************************/
package org.eclipse.osgi.tests.eventmgr;

import static org.junit.Assert.*;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.AbstractMap;
import java.util.AbstractSet;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.ConcurrentModificationException;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import org.eclipse.osgi.framework.eventmgr.CopyOnWriteIdentityMap;
import org.eclipse.osgi.framework.eventmgr.EventManager;
import org.eclipse.osgi.framework.eventmgr.ListenerQueue;
import org.junit.Test;

public class CopyOnWriteIdentityMapArrayTests {

	@Test
	public void retainedMapAndSnapshotsDoNotStoreEntryObjects() throws Exception {
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		for (int i = 0; i < 128; i++) {
			map.put(new Object(), new Object());
		}
		assertNoRetainedEntries(map);
		assertNoRetainedEntries(new CopyOnWriteIdentityMap<>(map));
		assertNoRetainedEntries(map.keySet());
		assertNoRetainedEntries(map.values());
		assertNoRetainedEntries(map.entrySet());
	}

	@Test
	public void eachPublicEntryProjectionIsFreshAndImmutable() {
		Object key = new Object();
		Object value = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(key, value);
		Set<Map.Entry<Object, Object>> snapshot = map.entrySet();
		Map.Entry<Object, Object> first = snapshot.iterator().next();
		Map.Entry<Object, Object> second = snapshot.iterator().next();
		assertNotSame(first, second);
		assertNotSame(first, map.entrySet().iterator().next());
		assertEquals(first, second);
		assertSame(key, first.getKey());
		assertSame(value, first.getValue());
		assertEquals(System.identityHashCode(key) ^ System.identityHashCode(value), first.hashCode());
		assertThrows(UnsupportedOperationException.class, () -> first.setValue(new Object()));
		map.remove(key);
		map.put(key, new Object());
		assertSame(value, first.getValue());
		assertSame(value, second.getValue());
	}

	@Test
	public void identityLookupAndSnapshotIsolationSurviveRemoveAndReinsert() {
		String first = new String("same");
		String second = new String("same");
		String value = new String("value");
		CopyOnWriteIdentityMap<String, String> map = new CopyOnWriteIdentityMap<>();
		map.put(first, value);
		map.put(second, null);
		assertEquals(2, map.size());
		assertFalse(map.containsKey(new String("same")));
		assertFalse(map.containsValue(new String("value")));
		assertTrue(map.containsValue(null));
		Set<String> keys = map.keySet();
		Collection<String> values = map.values();
		Set<Map.Entry<String, String>> entries = map.entrySet();
		map.clear();
		map.put(first, "new");
		assertArrayEquals(new Object[] { first, second }, keys.toArray());
		assertArrayEquals(new Object[] { value, null }, values.toArray());
		assertSame(value, entries.iterator().next().getValue());
		keys.clear();
		assertEquals(2, entries.size());
		assertEquals(1, map.size());
		assertThrows(NullPointerException.class, () -> map.get(null));
		assertThrows(NullPointerException.class, () -> map.containsKey(null));
		assertThrows(NullPointerException.class, () -> map.remove(null));
		assertThrows(NullPointerException.class, () -> map.put(null, "x"));
	}

	@Test
	public void copyingSharesOnlyImmutableGenerations() {
		Object key = new Object();
		Object before = new Object();
		Object after = new Object();
		CopyOnWriteIdentityMap<Object, Object> original = new CopyOnWriteIdentityMap<>();
		original.put(key, before);
		CopyOnWriteIdentityMap<Object, Object> copy = new CopyOnWriteIdentityMap<>(original);
		assertSame(before, original.put(key, before));
		assertSame(before, original.put(key, after));
		assertSame(before, copy.get(key));
		copy.clear();
		assertSame(after, original.get(key));
	}

	@Test
	public void bulkSourceCallbacksKeepOrderAndFailureIsAtomic() {
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		Object incumbent = new Object();
		Object reentrant = new Object();
		Object value = new Object();
		map.put(incumbent, value);
		List<String> trace = new ArrayList<>();
		Map.Entry<Object, Object> bad = new Map.Entry<>() {
			@Override public Object getKey() { trace.add("key"); map.put(reentrant, value); return null; }
			@Override public Object getValue() { trace.add("value"); return value; }
			@Override public Object setValue(Object ignored) { throw new UnsupportedOperationException(); }
		};
		Map<Object, Object> source = source(1, List.of(bad), trace);
		assertThrows(NullPointerException.class, () -> map.putAll(source));
		assertEquals(List.of("size", "entries", "iterator", "next", "key", "value"), trace);
		assertArrayEquals(new Object[] { incumbent, reentrant }, map.keySet().toArray());
		assertSame(value, map.get(incumbent));
	}

	@Test
	public void bulkSourceReportedSizeAndDuplicateIdentityArePreserved() {
		Object first = new Object();
		Object second = new Object();
		Object a = new Object();
		Object b = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(first, a);
		map.putAll(source(2, List.of(entry(second, a), entry(first, b), entry(new Object(), a)), new ArrayList<>()));
		assertArrayEquals(new Object[] { first, second }, map.keySet().toArray());
		assertSame(b, map.get(first));
		assertSame(a, map.get(second));
		assertThrows(NoSuchElementException.class, () -> map.putAll(source(2, List.of(entry(first, a)), new ArrayList<>())));
		assertSame(b, map.get(first));
		map.putAll(map);
		assertArrayEquals(new Object[] { first, second }, map.keySet().toArray());
	}

	@Test
	public void keyArrayBulkKeepsOrderAndValidatesBeforePublishing() {
		Object first = new Object();
		Object second = new Object();
		Object third = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(first, third);
		map.putAll(new Object[] { second, first, second });
		assertArrayEquals(new Object[] { first, second }, map.keySet().toArray());
		assertNull(map.get(first));
		assertNull(map.get(second));
		assertThrows(NullPointerException.class, () -> map.putAll(new Object[] { third, null }));
		assertFalse(map.containsKey(third));
	}

	@Test
	public void snapshotIteratorKeepsOriginalRemovalAndFailureBehavior() {
		Object first = new Object();
		Object second = new Object();
		Object third = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.putAll(new Object[] { first, second, third });
		Set<Object> keys = map.keySet();
		Iterator<Object> iterator = keys.iterator();
		assertThrows(IllegalStateException.class, iterator::remove);
		assertSame(first, iterator.next());
		assertSame(second, iterator.next());
		iterator.remove();
		// The original iterator permits removing the previous element again.
		iterator.remove();
		assertArrayEquals(new Object[] { third }, keys.toArray());
		assertSame(third, iterator.next());
		assertFalse(iterator.hasNext());
		assertThrows(NoSuchElementException.class, iterator::next);
		Set<Object> another = map.keySet();
		Iterator<Object> stale = another.iterator();
		another.remove(second);
		assertTrue(stale.hasNext());
		assertThrows(ConcurrentModificationException.class, stale::next);
		assertThrows(ConcurrentModificationException.class, stale::remove);
		assertEquals(3, map.size());
	}

	@Test
	public void entryRemovalCapturesPairBeforeReentrantEntryCallbacks() {
		Object key = new Object();
		Object value = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(key, value);
		Set<Map.Entry<Object, Object>> entries = map.entrySet();
		List<String> trace = new ArrayList<>();
		Map.Entry<Object, Object> probe = new Map.Entry<>() {
			@Override public Object getKey() { trace.add("key"); entries.clear(); return key; }
			@Override public Object getValue() { trace.add("value"); return value; }
			@Override public Object setValue(Object ignored) { throw new UnsupportedOperationException(); }
		};
		assertThrows(NegativeArraySizeException.class, () -> entries.remove(probe));
		assertEquals(List.of("key", "value"), trace);
		assertTrue(entries.isEmpty());
		assertSame(value, map.get(key));
		assertThrows(NullPointerException.class, () -> entries.remove(null));
		assertFalse(entries.remove(new Object()));
	}

	@Test
	public void snapshotEntryComparisonsUseIdentityAndKeepGetterShortCircuiting() {
		Object key = new Object();
		Object value = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(key, value);
		List<String> trace = new ArrayList<>();
		Map.Entry<Object, Object> miss = new Map.Entry<>() {
			@Override public Object getKey() { trace.add("key"); return new Object(); }
			@Override public Object getValue() { fail("value getter after unequal key"); return null; }
			@Override public Object setValue(Object ignored) { throw new UnsupportedOperationException(); }
		};
		assertFalse(map.entrySet().remove(miss));
		assertEquals(List.of("key"), trace);
		assertTrue(map.entrySet().remove(entry(key, value)));
		assertEquals(1, map.size());
	}

	@Test
	public void forEachUsesOneSnapshotDuringReentrantMapWrites() {
		Object first = new Object();
		Object second = new Object();
		Object a = new Object();
		Object b = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(first, a);
		map.put(second, b);
		List<Object> seen = new ArrayList<>();
		map.forEach((key, value) -> {
			seen.add(key); seen.add(value);
			map.clear(); map.put(second, a);
		});
		assertEquals(Arrays.asList(first, a, second, b), seen);
		assertSame(a, map.get(second));
		assertThrows(NullPointerException.class, () -> map.forEach(null));
		map.clear();
		assertThrows(NullPointerException.class, () -> map.forEach(null));
	}

	@Test
	public void inheritedReplaceAllKeepsFirstCallbackThenUnsupportedEntryWrite() {
		Object first = new Object();
		Object second = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.putAll(new Object[] { first, second });
		List<Object> seen = new ArrayList<>();
		assertThrows(UnsupportedOperationException.class, () -> map.replaceAll((key, value) -> {
			seen.add(key); return key;
		}));
		assertEquals(List.of(first), seen);
		assertNull(map.get(first));
		map.clear();
		map.replaceAll((key, value) -> { fail("empty callback"); return value; });
	}

	@Test
	public void concurrentBulkPublicationKeepsKeysAndValuesInOneGeneration() throws Exception {
		Object first = new Object();
		Object second = new Object();
		Object a = new Object();
		Object b = new Object();
		CopyOnWriteIdentityMap<Object, Object> left = new CopyOnWriteIdentityMap<>();
		CopyOnWriteIdentityMap<Object, Object> right = new CopyOnWriteIdentityMap<>();
		left.put(first, a); left.put(second, a);
		right.put(first, b); right.put(second, b);
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>(left);
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService workers = Executors.newFixedThreadPool(3);
		AtomicReference<Throwable> failure = new AtomicReference<>();
		try {
			Future<?> writer = workers.submit(() -> {
				await(start);
				for (int i = 0; i < 20000; i++) { map.putAll((i & 1) == 0 ? right : left); }
			});
			Runnable reader = () -> {
				await(start);
				try {
					for (int i = 0; i < 10000; i++) {
						Iterator<Map.Entry<Object, Object>> entries = map.entrySet().iterator();
						Map.Entry<Object, Object> one = entries.next();
						Map.Entry<Object, Object> two = entries.next();
						assertSame(first, one.getKey()); assertSame(second, two.getKey());
						assertSame(one.getValue(), two.getValue());
						assertTrue(one.getValue() == a || one.getValue() == b);
						assertFalse(entries.hasNext());
						List<Object> values = new ArrayList<>(2);
						map.forEach((key, value) -> values.add(value));
						assertSame(values.get(0), values.get(1));
					}
				} catch (Throwable ex) { failure.compareAndSet(null, ex); }
			};
			Future<?> firstReader = workers.submit(reader);
			Future<?> secondReader = workers.submit(reader);
			start.countDown();
			writer.get(30, TimeUnit.SECONDS);
			firstReader.get(30, TimeUnit.SECONDS);
			secondReader.get(30, TimeUnit.SECONDS);
			if (failure.get() != null) { throw new AssertionError(failure.get()); }
		} finally { workers.shutdownNow(); }
	}

	@Test
	public void subclassForEachStillUsesItsOverriddenEntryView() {
		Object originalKey = new Object();
		Object projectedKey = new Object();
		Object projectedValue = new Object();
		List<String> trace = new ArrayList<>();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>() {
			@Override public Set<Map.Entry<Object, Object>> entrySet() {
				trace.add("entries");
				return Set.of(entry(projectedKey, projectedValue));
			}
		};
		map.put(originalKey, null);
		List<Object> seen = new ArrayList<>();
		map.forEach((key, value) -> { seen.add(key); seen.add(value); });
		assertEquals(List.of("entries"), trace);
		assertEquals(List.of(projectedKey, projectedValue), seen);
	}

	@Test
	public void originalListenerQueueDispatchKeepsSnapshotAndContinuesAfterCallbackFailure() {
		Object first = new Object();
		Object second = new Object();
		Object a = new Object();
		Object b = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(first, a); map.put(second, b);
		EventManager manager = new EventManager("identity-map-array-sync-test");
		try {
			ListenerQueue<Object, Object, Object> queue = new ListenerQueue<>(manager);
			List<Object> seen = new ArrayList<>();
			Object event = new Object();
			queue.queueListeners(map.entrySet(), (key, value, action, actualEvent) -> {
				assertEquals(17, action); assertSame(event, actualEvent);
				seen.add(key); seen.add(value);
				if (key == first) { throw new IllegalStateException("expected listener failure"); }
			});
			map.clear();
			queue.dispatchEventSynchronous(17, event);
			assertEquals(List.of(first, a, second, b), seen);
		} finally { manager.close(); }
	}

	@Test
	public void originalListenerQueueAsynchronousDispatchKeepsSnapshot() throws Exception {
		Object first = new Object();
		Object second = new Object();
		CopyOnWriteIdentityMap<Object, Object> map = new CopyOnWriteIdentityMap<>();
		map.put(first, second); map.put(second, first);
		EventManager manager = new EventManager("identity-map-array-async-test");
		try {
			ListenerQueue<Object, Object, Object> queue = new ListenerQueue<>(manager);
			List<Object> seen = java.util.Collections.synchronizedList(new ArrayList<>());
			CountDownLatch delivered = new CountDownLatch(2);
			queue.queueListeners(map.entrySet(), (key, value, action, event) -> {
				seen.add(key); seen.add(value); delivered.countDown();
			});
			map.clear(); map.put(first, first);
			queue.dispatchEventAsynchronous(3, null);
			assertTrue(delivered.await(10, TimeUnit.SECONDS));
			assertEquals(List.of(first, second, second, first), seen);
		} finally { manager.close(); }
	}

	private static void await(CountDownLatch start) {
		try { start.await(); }
		catch (InterruptedException ex) { Thread.currentThread().interrupt(); throw new AssertionError(ex); }
	}

	private static <K, V> Map.Entry<K, V> entry(K key, V value) {
		return new AbstractMap.SimpleImmutableEntry<>(key, value);
	}

	private static <K, V> Map<K, V> source(int size, List<Map.Entry<K, V>> entries, List<String> trace) {
		return new AbstractMap<>() {
			@Override public int size() { trace.add("size"); return size; }
			@Override public Set<Map.Entry<K, V>> entrySet() {
				trace.add("entries");
				return new AbstractSet<>() {
					@Override public int size() { throw new AssertionError("entry-set size"); }
					@Override public Iterator<Map.Entry<K, V>> iterator() {
						trace.add("iterator");
						Iterator<Map.Entry<K, V>> delegate = entries.iterator();
						return new Iterator<>() {
							@Override public boolean hasNext() { throw new AssertionError("hasNext"); }
							@Override public Map.Entry<K, V> next() { trace.add("next"); return delegate.next(); }
						};
					}
				};
			}
		};
	}

	private static void assertNoRetainedEntries(Object owner) throws Exception {
		Set<Object> visited = java.util.Collections.newSetFromMap(new IdentityHashMap<>());
		ArrayDeque<Object> pending = new ArrayDeque<>();
		pending.add(owner);
		while (!pending.isEmpty()) {
			Object value = pending.removeFirst();
			if (!visited.add(value)) { continue; }
			assertFalse("retained per-mapping Entry: " + value.getClass(), value instanceof Map.Entry<?, ?>);
			Class<?> type = value.getClass();
			if (type.isArray() && !type.getComponentType().isPrimitive()) {
				for (int i = 0; i < Array.getLength(value); i++) {
					Object element = Array.get(value, i);
					if (element != null) { pending.add(element); }
				}
			} else if (type.getName().startsWith(CopyOnWriteIdentityMap.class.getName())) {
				for (Field field : type.getDeclaredFields()) {
					if (!Modifier.isStatic(field.getModifiers()) && !field.getType().isPrimitive()) {
						field.setAccessible(true);
						Object nested = field.get(value);
						if (nested != null) { pending.add(nested); }
					}
				}
			}
		}
	}
}
