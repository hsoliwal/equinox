/*******************************************************************************
 * Copyright (c) 2003, 2020 IBM Corporation and others.
 *
 * This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License 2.0
 * which accompanies this distribution, and is available at
 * https://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *
 * Contributors:
 *     IBM Corporation - initial API and implementation
 *******************************************************************************/

package org.eclipse.osgi.framework.eventmgr;

import static java.util.Objects.requireNonNull;

import java.util.AbstractCollection;
import java.util.AbstractSet;
import java.util.Arrays;
import java.util.Collection;
import java.util.ConcurrentModificationException;
import java.util.Iterator;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.Set;
import java.util.function.BiConsumer;

/**
 * A copy-on-write identity map. Write operations result in copying the underlying data so that
 * simultaneous read operations are not affected.
 * This allows for safe, unsynchronized traversal.
 *
 * <p>
 * Note: This class uses identity for key and value comparison, not equals.
 *
 * @since 3.5
 */
public class CopyOnWriteIdentityMap<K, V> implements Map<K, V> {
	/**
	 * The empty immutable generation singleton.
	 */
	private static final Table<?, ?> emptyTable = new Table<>(new Object[0], new Object[0]);

	/**
	 * Keys and values are published together as one immutable generation. Readers
	 * capture this volatile reference once and never observe partially copied lanes.
	 */
	private volatile Table<K, V> entries;

	/**
	 * Creates an empty map.
	 */
	public CopyOnWriteIdentityMap() {
		entries = empty();
	}

	/**
	 * Copy constructor.
	 *
	 * @param source The CopyOnWriteMap to copy.
	 */
	public CopyOnWriteIdentityMap(CopyOnWriteIdentityMap<? extends K, ? extends V> source) {
		@SuppressWarnings("unchecked")
		Table<K, V> toCopy = (Table<K, V>) source.entries();
		this.entries = toCopy;
	}

	/* These methods modify the map and are synchronized. */

	/**
	 * Add a key, value pair to the map. If the key object is already in the map,
	 * then its value is replaced with the new value. Keys are compared using
	 * identity.
	 *
	 * @param key   The key object to be added to the list.
	 * @param value The value object to be associated with the key. This may be
	 *              null.
	 * @return <code>null</code> if the specified key was newly added to the map.
	 *         Otherwise the previous value of the key.
	 * @throws NullPointerException If key is null.
	 */
	@Override
	public synchronized V put(K key, V value) {
		requireNonNull(key);

		Table<K, V> current = entries;
		int size = current.size();
		for (int i = 0; i < size; i++) {
			if (current.keys[i] == key) {
				V v = current.value(i);
				if (v == value) {
					return v;
				}
				Object[] newValues = current.values.clone();
				newValues[i] = value;
				entries = new Table<>(current.keys, newValues);
				return v;
			}
		}

		Object[] newKeys = Arrays.copyOf(current.keys, size + 1);
		Object[] newValues = Arrays.copyOf(current.values, size + 1);
		newKeys[size] = key;
		newValues[size] = value;
		entries = new Table<>(newKeys, newValues);
		return null;
	}

	/**
	 * Add all the entries from the specified map to this map.
	 *
	 * @param source The map whose entries are to be added to this map.
	 */
	@Override
	public void putAll(Map<? extends K, ? extends V> source) {
		int sourceSize = source.size();
		if (sourceSize == 0) {
			return;
		}
		if (source instanceof CopyOnWriteIdentityMap<?, ?>) {
			putAll(((CopyOnWriteIdentityMap<? extends K, ? extends V>) source).entries());
			return;
		}

		Object[] keys = new Object[sourceSize];
		Object[] values = new Object[sourceSize];
		Iterator<? extends Map.Entry<? extends K, ? extends V>> iter = source.entrySet().iterator();
		for (int i = 0; i < sourceSize; i++) {
			Map.Entry<? extends K, ? extends V> mapEntry = iter.next();
			K key = mapEntry.getKey();
			V value = mapEntry.getValue();
			// Both getters precede validation, as in the immutable entry constructor.
			keys[i] = requireNonNull(key);
			values[i] = value;
		}
		putAll(new Table<K, V>(keys, values));
	}

	/**
	 * Add all the keys from the specified array to this map with the value
	 * <code>null</code>.
	 *
	 * @param keys The array of keys to be added to this map.
	 */
	public <L extends K> void putAll(L[] keys) {
		int sourceSize = keys.length;
		if (sourceSize == 0) {
			return;
		}
		Object[] newKeys = new Object[sourceSize];
		Object[] newValues = new Object[sourceSize];
		for (int i = 0; i < sourceSize; i++) {
			newKeys[i] = requireNonNull(keys[i]);
		}
		putAll(new Table<K, V>(newKeys, newValues));
	}

	/**
	 * Add all the entries to this map.
	 *
	 * @param toCopy Immutable key/value generation to add to this map.
	 */
	private synchronized void putAll(Table<? extends K, ? extends V> toCopy) {
		int sourceSize = toCopy.size();
		Table<K, V> current = entries;
		int size = current.size();
		Object[] newKeys = Arrays.copyOf(current.keys, size + sourceSize);
		Object[] newValues = Arrays.copyOf(current.values, size + sourceSize);
		copy: for (int n = 0; n < sourceSize; n++) {
			Object key = toCopy.keys[n];
			Object value = toCopy.values[n];
			for (int i = 0; i < size; i++) {
				if (newKeys[i] == key) {
					newValues[i] = value;
					continue copy;
				}
			}
			newKeys[size] = key;
			newValues[size] = value;
			size++;
		}
		if (size != newKeys.length) {
			newKeys = Arrays.copyOf(newKeys, size);
			newValues = Arrays.copyOf(newValues, size);
		}
		entries = new Table<>(newKeys, newValues);
	}

	/**
	 * Remove a key from the map and returns the value associated with the key. Key
	 * objects are compared using identity.
	 *
	 * @param key The key object to be removed from the map.
	 * @return <code>null</code> if the key was not in the list. Otherwise, the
	 *         value associated with the key.
	 * @throws NullPointerException If key is null.
	 */
	@Override
	public synchronized V remove(Object key) {
		requireNonNull(key);

		int size = entries.size();
		for (int i = 0; i < size; i++) {
			if (entries.keys[i] == key) {
				V v = entries.value(i);
				entries = removeEntry(entries, i);
				return v;
			}
		}
		return null;
	}

	/**
	 * Static method used to return a generation with the ith mapping removed.
	 */
	static <K, V> Table<K, V> removeEntry(final Table<K, V> entries, final int i) {
		int size = entries.size();
		if (size == 1) {
			return empty();
		}
		Object[] newKeys = new Object[size - 1];
		Object[] newValues = new Object[size - 1];
		if (i > 0) {
			System.arraycopy(entries.keys, 0, newKeys, 0, i);
			System.arraycopy(entries.values, 0, newValues, 0, i);
		}
		int next = size - 1 - i;
		if (next > 0) {
			System.arraycopy(entries.keys, i + 1, newKeys, i, next);
			System.arraycopy(entries.values, i + 1, newValues, i, next);
		}
		return new Table<>(newKeys, newValues);
	}

	/**
	 * Remove all entries from the map.
	 */
	@Override
	public synchronized void clear() {
		entries = empty();
	}

	/* These methods only read the map and are not synchronized. */

	/**
	 * Accessor for methods which only read the entries.
	 * @return The immutable generation. Callers MUST NOT modify its arrays.
	 */
	private Table<K, V> entries() {
		return entries;
	}

	/**
	 * Return the static empty generation generically type safe.
	 * @return The empty generation.
	 */
	@SuppressWarnings("unchecked")
	static <K, V> Table<K, V> empty() {
		return (Table<K, V>) emptyTable;
	}

	/**
	 * Is the map empty?
	 *
	 * @return <code>true</code> if the list is empty.
	 */
	@Override
	public boolean isEmpty() {
		return size() == 0;
	}

	/**
	 * Return the number of entries in the map.
	 *
	 * @return The number of entries in the map.
	 */
	@Override
	public int size() {
		return entries().size();
	}

	/**
	 * Return the value object for the specified key. Keys are compared using
	 * identity.
	 *
	 * @param key The key object.
	 * @return The value object for the specified key.
	 * @throws NullPointerException If key is null.
	 */
	@Override
	public V get(Object key) {
		requireNonNull(key);

		Table<K, V> current = entries();
		for (int i = 0; i < current.size(); i++) {
			if (current.keys[i] == key) {
				return current.value(i);
			}
		}
		return null;
	}

	/**
	 * Check if the map contains the specified key. Keys are compared using
	 * identity.
	 *
	 * @param key The key object.
	 * @return <code>true</code> if the specified key is in the map.
	 * @throws NullPointerException If key is null.
	 */
	@Override
	public boolean containsKey(Object key) {
		requireNonNull(key);

		for (Object currentKey : entries().keys) {
			if (currentKey == key) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Check if the map contains the specified value.
	 * Values are compared using identity.
	 *
	 * @param value The value object.
	 * @return <code>true</code> if the specified value is in the map.
	 */
	@Override
	public boolean containsValue(Object value) {
		for (Object currentValue : entries().values) {
			if (currentValue == value) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Returns a snapshot of the entries in this map.
	 * Changes to the returned set or this map will not affect each other.
	 *
	 * @return A Set of Map.Entry for each entry in this map.
	 * The entries returned by the set cannot be modified.
	 */
	@Override
	public Set<Map.Entry<K, V>> entrySet() {
		return new Snapshot<>(entries()).entrySet();
	}

	/**
	 * Returns a snapshot of the keys in this map.
	 * Changes to the returned set or this map will not affect each other.
	 *
	 * @return A Set of the key objects in this map
	 */
	@Override
	public Set<K> keySet() {
		return new Snapshot<>(entries()).keySet();
	}

	/**
	 * Returns a snapshot of the values in this map.
	 * Changes to the returned set or this map will not affect each other.
	 *
	 * @return A Collection of the value objects in this map.
	 */
	@Override
	public Collection<V> values() {
		return new Snapshot<>(entries()).values();
	}

	/**
	 * Traverse one immutable generation without allocating public entry projections.
	 */
	@Override
	public void forEach(BiConsumer<? super K, ? super V> action) {
		requireNonNull(action);
		if (getClass() != CopyOnWriteIdentityMap.class) {
			// A subclass may have overridden the entry-set traversal contract.
			Map.super.forEach(action);
			return;
		}
		Table<K, V> current = entries();
		for (int i = 0; i < current.size(); i++) {
			action.accept(current.key(i), current.value(i));
		}
	}

	/**
	 * One immutable copy-on-write generation. Arrays are private owner state and
	 * are never changed after publication; replacing values can share the key lane.
	 */
	static private final class Table<K, V> {
		final Object[] keys;
		final Object[] values;

		Table(Object[] keys, Object[] values) {
			this.keys = keys;
			this.values = values;
		}

		int size() {
			return keys.length;
		}

		@SuppressWarnings("unchecked")
		K key(int index) {
			return (K) keys[index];
		}

		@SuppressWarnings("unchecked")
		V value(int index) {
			return (V) values[index];
		}

		boolean entryEquals(int index, Object other) {
			// Capture both references before invoking the external entry's getters.
			Object key = keys[index];
			Object value = values[index];
			if (!(other instanceof Map.Entry<?, ?>)) {
				return false;
			}
			Map.Entry<?, ?> entry = (Map.Entry<?, ?>) other;
			return key == entry.getKey() && value == entry.getValue();
		}
	}

	/**
	 * This class represents a caller-owned projection of an entry in this identity map.
	 * Entry is immutable.
	 */
	static private final class Entry<K, V> implements Map.Entry<K, V> {
		/**
		 * Key object.
		 */
		final K key;

		/**
		 * Value object.
		 */
		final V value;

		/**
		 * Constructor for map entry.
		 * 
		 * @param key   Key object in entry. Used for uniqueness.
		 * @param value Value object stored with key object.
		 * @throws NullPointerException If key is null.
		 */
		Entry(final K key, final V value) {
			this.key = requireNonNull(key);
			this.value = value;
		}

		@Override
		public K getKey() {
			return key;
		}

		@Override
		public V getValue() {
			return value;
		}

		@Override
		public V setValue(V value) {
			throw new UnsupportedOperationException(); // entries cannot be modified.
		}

		@Override
		public String toString() {
			return key + "=" + value; //$NON-NLS-1$
		}

		@Override
		public int hashCode() {
			return System.identityHashCode(key) ^ System.identityHashCode(value);
		}

		@Override
		public boolean equals(Object obj) {
			if (obj == this) {
				return true;
			}

			if (!(obj instanceof Map.Entry)) {
				return false;
			}

			Map.Entry<?, ?> e = (Map.Entry<?, ?>) obj;
			return (key == e.getKey()) && (value == e.getValue());
		}
	}

	/**
	 * A snapshot of the entries in the map. This snapshot used by
	 * the map collection views. Changes made by the collection
	 * views only mutate the snapshot and not the map. The collection
	 * views only allow removal not addition.
	 */
	static private final class Snapshot<K, V> {
		volatile Table<K, V> entries;

		Snapshot(Table<K, V> e) {
			entries = e;
		}

		Table<K, V> entries() {
			return entries;
		}

		synchronized void removeEntry(int i) {
			entries = CopyOnWriteIdentityMap.removeEntry(entries, i);
		}

		synchronized void clearEntries() {
			entries = CopyOnWriteIdentityMap.empty();
		}

		Set<Map.Entry<K, V>> entrySet() {
			return new EntrySet();
		}

		Set<K> keySet() {
			return new KeySet();
		}

		Collection<V> values() {
			return new ValueCollection();
		}

		/**
		 * Entry set view over the snapshot.
		 */
		private final class EntrySet extends AbstractSet<Map.Entry<K, V>> {
			EntrySet() {
				super();
			}

			@Override
			public Iterator<Map.Entry<K, V>> iterator() {
				return new EntryIterator();
			}

			@Override
			public int size() {
				return entries().size();
			}

			@Override
			public boolean remove(Object o) {
				requireNonNull(o);

				synchronized (Snapshot.this) {
					int size = entries.size();
					for (int i = 0; i < size; i++) {
						if (entries.entryEquals(i, o)) {
							removeEntry(i);
							return true;
						}
					}
				}
				return false;
			}

			@Override
			public void clear() {
				clearEntries();
			}
		}

		/**
		 * Entry set iterator over the snapshot.
		 */
		private final class EntryIterator extends SnapshotIterator<Map.Entry<K, V>> {
			EntryIterator() {
				super();
			}

			@Override
			public Map.Entry<K, V> next() {
				Table<K, V> current = entries();
				int index = nextIndex(current);
				return new Entry<>(current.key(index), current.value(index));
			}
		}

		/**
		 * Key set view over the snapshot.
		 */
		private final class KeySet extends AbstractSet<K> {
			KeySet() {
				super();
			}

			@Override
			public Iterator<K> iterator() {
				return new KeyIterator();
			}

			@Override
			public int size() {
				return entries().size();
			}

			@Override
			public boolean remove(Object o) {
				requireNonNull(o);

				synchronized (Snapshot.this) {
					int size = entries.size();
					for (int i = 0; i < size; i++) {
						if (entries.keys[i] == o) {
							removeEntry(i);
							return true;
						}
					}
				}
				return false;
			}

			@Override
			public void clear() {
				clearEntries();
			}
		}

		/**
		 * Key set iterator over the snapshot.
		 */
		private final class KeyIterator extends SnapshotIterator<K> {
			KeyIterator() {
				super();
			}

			@Override
			public K next() {
				Table<K, V> current = entries();
				return current.key(nextIndex(current));
			}
		}

		/**
		 * Value collection view over the snapshot.
		 */
		private final class ValueCollection extends AbstractCollection<V> {
			ValueCollection() {
				super();
			}

			@Override
			public Iterator<V> iterator() {
				return new ValueIterator();
			}

			@Override
			public int size() {
				return entries().size();
			}

			@Override
			public boolean remove(Object o) {
				requireNonNull(o);

				synchronized (Snapshot.this) {
					int size = entries.size();
					for (int i = 0; i < size; i++) {
						if (entries.values[i] == o) {
							removeEntry(i);
							return true;
						}
					}
				}
				return false;
			}

			@Override
			public void clear() {
				clearEntries();
			}
		}

		/**
		 * Value collection iterator over the snapshot.
		 */
		private final class ValueIterator extends SnapshotIterator<V> {
			ValueIterator() {
				super();
			}

			@Override
			public V next() {
				Table<K, V> current = entries();
				return current.value(nextIndex(current));
			}
		}

		/**
		 * Base iterator class handling removal and concurrent modifications.
		 */
		private abstract class SnapshotIterator<E> implements Iterator<E> {
			private int length;
			private int cursor;

			SnapshotIterator() {
				length = entries().size();
				cursor = 0;
			}

			@Override
			public final boolean hasNext() {
				return cursor < length;
			}

			protected final int nextIndex(Table<K, V> current) {
				if (length != current.size()) {
					throw new ConcurrentModificationException();
				}
				if (cursor == length) {
					throw new NoSuchElementException();
				}
				return cursor++;
			}

			@Override
			public final void remove() {
				if (length != entries().size()) {
					throw new ConcurrentModificationException();
				}
				if (cursor == 0) {
					throw new IllegalStateException();
				}
				cursor--;
				removeEntry(cursor);
				length = entries().size();
			}
		}
	}
}
